/* Architecture Explorer: bounded source-backed views; no remote resources. */
'use strict';
(() => {
  const $ = id => document.getElementById(id);
  const saved = !!window.ARCHITECTURE_SAVED;
  const repositoryMode = !!document.querySelector('meta[name="repository-map"]');
  let repositoryPage;
  let sourceView, allFileDeclarations=false;
  let c4Map, contextOverview;
  let view, cy, selected, selectedFact, query = {method:'graph.overview',level:'context'}, navigation, layoutReadyQuery, searchTimer, inspection = 0, request = 0, layoutGeneration = 0, lastLayoutKey, visibleLayout, edgeHoverNode, worker, streamEpoch;
  const text = (tag,value,cls) => {const e=document.createElement(tag);e.textContent=value;if(cls)e.className=cls;return e;};
  const button = (label,action,cls) => {const e=text('button',label,cls);e.addEventListener('click',action);return e;};
  function createTerminal(){
    const toggle=$('terminal-toggle'),output=$('terminal-output'),history=[];
    const capacity=250;
    function row(entry){
      const line=text('div','','terminal-entry');
      line.dataset.level=entry.level;
      line.append(text('time',entry.time),text('span',entry.level.toUpperCase(),'terminal-level'),text('span',entry.message,'terminal-message'));
      return line;
    }
    function setOpen(open){
      output.hidden=!open;
      toggle.setAttribute('aria-expanded',String(open));
      toggle.setAttribute('aria-label','Terminal');
      toggle.dataset.unread='false';
      if(open){
        output.replaceChildren(...history.map(row));
        output.scrollTop=output.scrollHeight;
      }else output.replaceChildren();
    }
    function write(level,message){
      const entry={level,time:new Date().toTimeString().slice(0,8),message:message.length>2048?message.slice(0,2047)+'…':message};
      history.push(entry);
      if(history.length>capacity)history.shift();
      if(output.hidden){
        if(level!=='info'&&toggle.dataset.unread!=='true'){
          toggle.dataset.unread='true';
          toggle.setAttribute('aria-label','Terminal · New diagnostics');
        }
        return;
      }
      const follow=output.scrollHeight-output.clientHeight-output.scrollTop<=3;
      output.append(row(entry));
      if(output.childElementCount>capacity)output.firstElementChild.remove();
      if(follow)output.scrollTop=output.scrollHeight;
    }
    toggle.onclick=()=>setOpen(output.hidden);
    setOpen(false);
    return {write,setOpen};
  }
  const terminal=createTerminal();
  const problem=error=>{if(error.code!=='VIEW_SUPERSEDED')terminal.write('error',error.message||String(error));};
  let destinationSerial=0,pendingDestination;
  const canvasReaders=new Map();
  function destinationPaint(){
    if(document.hidden===false)return new Promise(done=>requestAnimationFrame(()=>setTimeout(done,0)));
    return Promise.resolve();
  }
  function beginDestination(title,detail='Loading…'){
    const token=++destinationSerial;pendingDestination={token,title};
    request++;inspection++;layoutGeneration++;layoutReadyQuery=undefined;lastLayoutKey=undefined;
    for(const id of ['workspace-actions','canvas-options','model-info']){const popover=$(id);if(popover.matches(':popover-open'))popover.hidePopover();}
    if(external?.panel?.open)external.panel.close();
    closePicker();c4Map?.dispose();c4Map=undefined;
    cy?.elements().remove();syncHeaderMenus([]);
    for(const id of ['graph','c4-surface','node-list','workspace-models','open-specification','specification-reader','spec-report','verification-summary','trace-steps','file-detail','more','follow-map'])$(id).hidden=true;
    $('specification-reader').replaceChildren();
    $('navigator').replaceChildren();$('node-list').replaceChildren();$('scope-count').textContent='…';
    $('view-title').textContent=title;$('breadcrumb').replaceChildren(text('span',title,'crumb-current'));
    $('counts').textContent='Loading…';$('snapshot-short').textContent='—';$('mode-label').textContent='';
    $('view-status').textContent='Loading…';$('footer-status').textContent=title+' · Loading…';
    $('inspector').replaceChildren(text('h2',title),text('p',detail));
    const empty=$('empty');empty.hidden=false;empty.dataset.state='loading';empty.setAttribute('role','status');empty.setAttribute('aria-live','polite');
    empty.replaceChildren(text('strong',title),text('p',detail));
    $('graph').setAttribute('aria-busy','true');
    for(const id of ['canvas-filter','local-filter','canvas-layout','local-layout','canvas-options-toggle','fit','zoom-in','zoom-out'])$(id).disabled=true;
    return token;
  }
  function finishDestination(){
    if(pendingDestination)$('inspector').replaceChildren(text('h2','No Selection'),text('p','Select an element to inspect its evidence.'));
    pendingDestination=undefined;delete $('empty').dataset.state;$('graph').setAttribute('aria-busy','false');
    for(const id of ['canvas-filter','local-filter','canvas-layout','local-layout','canvas-options-toggle','fit','zoom-in','zoom-out'])$(id).disabled=false;
  }
  function failDestination(token,error,retry){
    if(token!==destinationSerial)return;
    const empty=$('empty');empty.hidden=false;empty.dataset.state='failed';empty.replaceChildren(text('strong','Unable to open '+pendingDestination.title),text('p',error.message||String(error)));
    if(retry)empty.append(button('Retry',retry));
    $('inspector').replaceChildren(text('h2',pendingDestination.title),text('p','Unavailable · '+(error.message||String(error))));
    $('graph').setAttribute('aria-busy','false');$('counts').textContent='Unavailable';$('footer-status').textContent='Unable to open '+pendingDestination.title;
    problem(error);
  }
  function routeTitle(route){
    return {context:'System Context',container:'Containers',module:'Modules',component:'Types & Groups',function:'Functions & Methods',file:'Files'}[route.level]||
      {'graph.cfg':'Control flow','graph.impact':'Impact','graph.neighbors':'Neighbors','graph.search':'Search results','workspace.specification':'Specification'}[route.method]||'Architecture';
  }
  function logGraph(view,label){
    terminal.write('info',label+' · '+view.nodes.length+' entities · '+view.edges.length+' relations · '+view.snapshotID.slice(0,8));
    for(const d of view.diagnostics||[])terminal.write(d.severity==='error'?'error':d.severity==='info'?'info':'warn',d.code+': '+d.message);
    if(view.truncated)terminal.write('warn','View budget reached. Use the next page or narrow this scope.');
  }
  function setupPaneResizing(){
    const workspace=$('workspace-body'),toggle=$('sidebar-toggle'),pane=$('navigator-pane'),handles={sidebar:$('sidebar-resizer'),inspector:$('inspector-resizer')};
    const preferred={sidebar:null,inspector:null};
    let current,drag,pending,frame,sidebarHidden=false;
    const clamp=(value,min,max)=>Math.max(min,Math.min(max,Math.round(value)));
    function defaults(){
      const style=getComputedStyle(workspace),sidebar=parseFloat(style.getPropertyValue('--sidebar-default')),inspector=parseFloat(style.getPropertyValue('--inspector-default'));
      if(!Number.isFinite(sidebar)||!Number.isFinite(inspector))throw Error('Panel layout defaults are unavailable.');
      return {sidebar,inspector};
    }
    function update(){
      const width=Math.floor(workspace.getBoundingClientRect().width);if(width<=0)return;
      const base=defaults(),available=base.sidebar>0,visible=available&&!sidebarHidden,canvas=Math.min(320,Math.floor(width*.55)),capacity=width-canvas;
      const sidebarMin=visible?160:0,inspectorMin=Math.min(200,capacity-sidebarMin);
      const inspector=clamp(preferred.inspector??base.inspector,inspectorMin,Math.min(480,capacity-sidebarMin));
      const sidebar=visible?clamp(preferred.sidebar??base.sidebar,sidebarMin,Math.min(400,capacity-inspector)):0;
      current={sidebar,inspector,visible,bounds:{sidebar:{min:sidebarMin,max:visible?Math.min(400,capacity-inspector):0},inspector:{min:inspectorMin,max:Math.min(480,capacity-sidebar)}}};
      pane.hidden=!visible;toggle.disabled=!available;
      toggle.setAttribute('aria-controls','navigator-pane');toggle.setAttribute('aria-expanded',String(visible));toggle.setAttribute('aria-label',visible?'Hide sidebar':'Show sidebar');toggle.title=available?(visible?'Hide sidebar':'Show sidebar'):'Sidebar is hidden at this window width';
      workspace.style.setProperty('--sidebar-width',sidebar+'px');workspace.style.setProperty('--inspector-width',inspector+'px');
      for(const name of ['sidebar','inspector']){
        const handle=handles[name],bounds=current.bounds[name],enabled=bounds.max>bounds.min;
        handle.hidden=name==='sidebar'&&!visible;handle.tabIndex=enabled?0:-1;
        handle.setAttribute('aria-disabled',String(!enabled));handle.setAttribute('aria-valuemin',String(bounds.min));handle.setAttribute('aria-valuemax',String(bounds.max));handle.setAttribute('aria-valuenow',String(current[name]));handle.setAttribute('aria-valuetext',current[name]+' pixels');
      }
      if(drag&&handles[drag.name].hidden)finish();
    }
    function change(name,value){
      if(!current||handles[name].hidden||!Number.isFinite(value))return;
      if(name==='sidebar')preferred.inspector=current.inspector;else if(current.visible)preferred.sidebar=current.sidebar;
      preferred[name]=clamp(value,current.bounds[name].min,current.bounds[name].max);update();
    }
    function flush(){
      if(frame!==undefined){cancelAnimationFrame(frame);frame=undefined;}
      const value=pending;pending=undefined;if(value)change(value.name,value.width);
    }
    function finish(){
      if(!drag)return;
      const previous=drag;drag=undefined;flush();
      const handle=handles[previous.name];handle.classList.remove('dragging');workspace.classList.remove('is-resizing');
      if(handle.hasPointerCapture(previous.pointerID))handle.releasePointerCapture(previous.pointerID);
    }
    for(const name of ['sidebar','inspector']){
      const handle=handles[name],direction=name==='sidebar'?1:-1;
      handle.addEventListener('pointerdown',event=>{
        if(drag||!current||handle.hidden||event.button!==0||event.isPrimary===false||current.bounds[name].min===current.bounds[name].max)return;
        event.preventDefault();handle.focus({preventScroll:true});handle.setPointerCapture(event.pointerId);
        drag={name,pointerID:event.pointerId,startX:event.clientX,startWidth:current[name]};handle.classList.add('dragging');workspace.classList.add('is-resizing');
      });
      handle.addEventListener('pointermove',event=>{
        if(!drag||drag.name!==name||drag.pointerID!==event.pointerId)return;
        event.preventDefault();pending={name,width:drag.startWidth+(event.clientX-drag.startX)*direction};
        if(frame===undefined)frame=requestAnimationFrame(()=>{frame=undefined;flush();});
      });
      for(const type of ['pointerup','pointercancel','lostpointercapture'])handle.addEventListener(type,event=>{if(drag?.name===name&&drag.pointerID===event.pointerId){if(type==='pointerup'&&Number.isFinite(event.clientX))pending={name,width:drag.startWidth+(event.clientX-drag.startX)*direction};finish();}});
      handle.addEventListener('dblclick',event=>{event.preventDefault();finish();change(name,defaults()[name]);});
      handle.addEventListener('keydown',event=>{
        if(drag){if(event.key==='Escape'){event.preventDefault();finish();}return;}
        if(!current||handle.hidden)return;
        const delta=(event.shiftKey?32:8)*direction;
        const value=event.key==='ArrowLeft'?current[name]-delta:event.key==='ArrowRight'?current[name]+delta:event.key==='Home'?current.bounds[name].min:event.key==='End'?current.bounds[name].max:undefined;
        if(value!==undefined){event.preventDefault();change(name,value);}
      });
    }
    toggle.addEventListener('click',()=>{if(defaults().sidebar<=0)return;finish();sidebarHidden=!sidebarHidden;update();});
    update();new ResizeObserver(update).observe(workspace);
    new ResizeObserver(()=>{if(cy)cy.resize();}).observe($('graph'));
  }
  const symbolKinds = {
    application:['Application','A'],dataStore:['Data store','DB'],softwareSystem:['Software System','Sy'],person:['Person','P'],workspace:['Workspace','W'],system:['System','Sy'],package:['Package','Pk'],module:['Module','M'],file:['File','F'],
    type:['Type','T'],class:['Class','C'],struct:['Struct','S'],enum:['Enum','E'],actor:['Actor','A'],interface:['Interface','I'],
    protocol:['Protocol','P'],trait:['Trait','Tr'],extension:['Extension','Ex'],implementation:['Impl','Im'],union:['Union','U'],
    function:['Function','ƒ'],method:['Method','m'],associatedFunction:['Associated Function','af'],initializer:['Initializer','in'],deinitializer:['Deinitializer','de'],
    property:['Property','p'],field:['Field','v'],constant:['Constant','c'],static:['Static','s'],typeAlias:['Type Alias','Ta'],associatedType:['Associated Type','At'],
    designGroup:['Design Group','G'],basicBlock:['Basic Block','B'],callSite:['Call Site','↗'],unresolvedSymbol:['Unresolved','?'],externalSymbol:['External','↗']
  };
  const diagramKinds = {
    repository:['Repository','R'],service:['Service','Sv'],network:['Network','N'],volume:['Volume','V'],
    entryPoint:['Entry point','Ep'],binding:['Imported binding','B'],variable:['Variable','v'],diagram:['Node','◇']
  };
  const kindKeys = new Map(Object.keys({...symbolKinds,...diagramKinds}).map(key=>[key.toLowerCase(),key]));
  const diagramRoles = new Map([
    ['compose service','service'],['referenced network','network'],['service entry point','entryPoint'],
    ['public entry point','entryPoint'],['imported binding','binding'],['package dependency','package'],
    ['type alias','typeAlias']
  ]);
  function symbolRole(node){
    if(node.canvas){
      const role=String(node.canvas.role||'').toLowerCase();
      return diagramRoles.get(role)||kindKeys.get(role)||(node.canvas.details?.checkouts?'repository':'diagram');
    }
    const kind=node.attributes?.['declaration.kind'];
    return Object.hasOwn(symbolKinds,kind)?kind:Object.hasOwn(symbolKinds,node.kind)?node.kind:'unknown';
  }
  function symbolKind(node){
    const key=symbolRole(node),kind=symbolKinds[key]||diagramKinds[key];
    return node.canvas?[node.canvas.role||'Node',kind[1]]:kind||[node.kind,'?'];
  }
  const roleAccents = {
    repository:'scope',service:'module',network:'interface',volume:'value',entryPoint:'function',binding:'alias',variable:'value',diagram:'unknown',
    application:'module',dataStore:'value',softwareSystem:'scope',person:'external',workspace:'scope',system:'scope',designGroup:'scope',package:'package',module:'module',file:'file',
    type:'type',class:'class',struct:'struct',enum:'enum',actor:'actor',interface:'interface',protocol:'interface',trait:'interface',union:'type',
    extension:'extension',implementation:'extension',function:'function',method:'method',associatedFunction:'function',initializer:'method',deinitializer:'method',
    property:'value',field:'value',constant:'constant',static:'constant',typeAlias:'alias',associatedType:'alias',basicBlock:'flow',callSite:'function',unresolvedSymbol:'unknown',externalSymbol:'external',unknown:'unknown'
  };
  const roleToken = node => roleAccents[symbolRole(node)];
  function roleMark(node){
    const mark=text('span',symbolKind(node)[1],'node-icon');mark.dataset.role=symbolRole(node);mark.style.setProperty('--role-accent',`var(--graph-role-${roleToken(node)})`);mark.setAttribute('aria-hidden','true');return mark;
  }
  function inspectorBadges(node){
    const role=text('span',symbolKind(node)[0],'badge role-badge');
    role.style.setProperty('--role-accent',`var(--graph-role-${roleToken(node)})`);
    const language=languageName(node);
    return language?[role,text('span',language,'badge')]:[role];
  }
  const nodeTitle = node => node.kind==='file'?(node.anchor?.path||node.name).split('/').pop():node.name;
  const languageAliases=new Map(Object.entries({
    ts:'typescript',tsx:'typescript',mts:'typescript',cts:'typescript',js:'javascript',jsx:'javascript',
    cjs:'javascript',mjs:'javascript',rs:'rust',py:'python',kt:'kotlin',golang:'go','c++':'cplusplus',cpp:'cplusplus',tf:'terraform'
  }));
  const languageNames=new Map(Object.entries({
    typescript:'TypeScript',javascript:'JavaScript',swift:'Swift',rust:'Rust',python:'Python',
    kotlin:'Kotlin',go:'Go',c:'C',cplusplus:'C++',terraform:'Terraform',java:'Java',lean:'Lean',tla:'TLA+',sql:'SQL'
  }));
  function languageKey(node){
    const key=typeof node.language==='string'?node.language.trim().toLowerCase():'';
    return key==='none'?'':languageAliases.get(key)||key;
  }
  function languageName(node){
    const key=languageKey(node);
    return key?(languageNames.get(key)||node.language.trim()):'';
  }
  // Simple Icons vectors; pinned source and CC0 terms: language-logos.LICENSE.md.
  const languagePaths = new Map([
    ["c","M16.5921 9.1962s-.354-3.298-3.627-3.39c-3.2741-.09-4.9552 2.474-4.9552 6.14 0 3.6651 1.858 6.5972 5.0451 6.5972 3.184 0 3.5381-3.665 3.5381-3.665l6.1041.365s.36 3.31-2.196 5.836c-2.552 2.5241-5.6901 2.9371-7.8762 2.9201-2.19-.017-5.2261.034-8.1602-2.97-2.938-3.0101-3.436-5.9302-3.436-8.8002 0-2.8701.556-6.6702 4.047-9.5502C7.444.72 9.849 0 12.254 0c10.0422 0 10.7172 9.2602 10.7172 9.2602z"],
    ["cplusplus","M22.394 6c-.167-.29-.398-.543-.652-.69L12.926.22c-.509-.294-1.34-.294-1.848 0L2.26 5.31c-.508.293-.923 1.013-.923 1.6v10.18c0 .294.104.62.271.91.167.29.398.543.652.69l8.816 5.09c.508.293 1.34.293 1.848 0l8.816-5.09c.254-.147.485-.4.652-.69.167-.29.27-.616.27-.91V6.91c.003-.294-.1-.62-.268-.91zM12 19.11c-3.92 0-7.109-3.19-7.109-7.11 0-3.92 3.19-7.11 7.11-7.11a7.133 7.133 0 016.156 3.553l-3.076 1.78a3.567 3.567 0 00-3.08-1.78A3.56 3.56 0 008.444 12 3.56 3.56 0 0012 15.555a3.57 3.57 0 003.08-1.778l3.078 1.78A7.135 7.135 0 0112 19.11zm7.11-6.715h-.79v.79h-.79v-.79h-.79v-.79h.79v-.79h.79v.79h.79zm2.962 0h-.79v.79h-.79v-.79h-.79v-.79h.79v-.79h.79v.79h.79z"],
    ["go","M1.811 10.231c-.047 0-.058-.023-.035-.059l.246-.315c.023-.035.081-.058.128-.058h4.172c.046 0 .058.035.035.07l-.199.303c-.023.036-.082.07-.117.07zM.047 11.306c-.047 0-.059-.023-.035-.058l.245-.316c.023-.035.082-.058.129-.058h5.328c.047 0 .07.035.058.07l-.093.28c-.012.047-.058.07-.105.07zm2.828 1.075c-.047 0-.059-.035-.035-.07l.163-.292c.023-.035.07-.07.117-.07h2.337c.047 0 .07.035.07.082l-.023.28c0 .047-.047.082-.082.082zm12.129-2.36c-.736.187-1.239.327-1.963.514-.176.046-.187.058-.34-.117-.174-.199-.303-.327-.548-.444-.737-.362-1.45-.257-2.115.175-.795.514-1.204 1.274-1.192 2.22.011.935.654 1.706 1.577 1.835.795.105 1.46-.175 1.987-.77.105-.13.198-.27.315-.434H10.47c-.245 0-.304-.152-.222-.35.152-.362.432-.97.596-1.274a.315.315 0 01.292-.187h4.253c-.023.316-.023.631-.07.947a4.983 4.983 0 01-.958 2.29c-.841 1.11-1.94 1.8-3.33 1.986-1.145.152-2.209-.07-3.143-.77-.865-.655-1.356-1.52-1.484-2.595-.152-1.274.222-2.419.993-3.424.83-1.086 1.928-1.776 3.272-2.02 1.098-.2 2.15-.07 3.096.571.62.41 1.063.97 1.356 1.648.07.105.023.164-.117.2m3.868 6.461c-1.064-.024-2.034-.328-2.852-1.029a3.665 3.665 0 01-1.262-2.255c-.21-1.32.152-2.489.947-3.529.853-1.122 1.881-1.706 3.272-1.95 1.192-.21 2.314-.095 3.33.595.923.63 1.496 1.484 1.648 2.605.198 1.578-.257 2.863-1.344 3.962-.771.783-1.718 1.273-2.805 1.495-.315.06-.63.07-.934.106zm2.78-4.72c-.011-.153-.011-.27-.034-.387-.21-1.157-1.274-1.81-2.384-1.554-1.087.245-1.788.935-2.045 2.033-.21.912.234 1.835 1.075 2.21.643.28 1.285.244 1.905-.07.923-.48 1.425-1.228 1.484-2.233z"],
    ["javascript","M0 0h24v24H0V0zm22.034 18.276c-.175-1.095-.888-2.015-3.003-2.873-.736-.345-1.554-.585-1.797-1.14-.091-.33-.105-.51-.046-.705.15-.646.915-.84 1.515-.66.39.12.75.42.976.9 1.034-.676 1.034-.676 1.755-1.125-.27-.42-.404-.601-.586-.78-.63-.705-1.469-1.065-2.834-1.034l-.705.089c-.676.165-1.32.525-1.71 1.005-1.14 1.291-.811 3.541.569 4.471 1.365 1.02 3.361 1.244 3.616 2.205.24 1.17-.87 1.545-1.966 1.41-.811-.18-1.26-.586-1.755-1.336l-1.83 1.051c.21.48.45.689.81 1.109 1.74 1.756 6.09 1.666 6.871-1.004.029-.09.24-.705.074-1.65l.046.067zm-8.983-7.245h-2.248c0 1.938-.009 3.864-.009 5.805 0 1.232.063 2.363-.138 2.711-.33.689-1.18.601-1.566.48-.396-.196-.597-.466-.83-.855-.063-.105-.11-.196-.127-.196l-1.825 1.125c.305.63.75 1.172 1.324 1.517.855.51 2.004.675 3.207.405.783-.226 1.458-.691 1.811-1.411.51-.93.402-2.07.397-3.346.012-2.054 0-4.109 0-6.179l.004-.056z"],
    ["kotlin","M24 24H0V0h24L12 12Z"],
    ["python","M11.858 0c-.978.005-1.913.088-2.736.234C6.7.662 6.26 1.558 6.26 3.21v2.182h5.725v.727H4.111c-1.664 0-3.121 1-3.577 2.903-.526 2.181-.549 3.542 0 5.82.407 1.694 1.379 2.902 3.043 2.902h1.969v-2.616c0-1.89 1.635-3.557 3.576-3.557h5.72c1.591 0 2.862-1.31 2.862-2.91v-5.45c0-1.553-1.309-2.718-2.863-2.977A18 18 0 0 0 11.858 0M8.762 1.755c.591 0 1.074.491 1.074 1.095 0 .601-.483 1.087-1.074 1.087A1.08 1.08 0 0 1 7.688 2.85c0-.604.48-1.095 1.074-1.095m9.656 4.364v2.543c0 1.971-1.671 3.63-3.577 3.63H9.122c-1.566 0-2.862 1.34-2.862 2.91v5.452c0 1.551 1.349 2.464 2.862 2.91 1.813.532 3.55.628 5.72 0 1.44-.418 2.862-1.258 2.862-2.91V18.47h-5.719v-.727h8.582c1.664 0 2.284-1.16 2.862-2.903.598-1.793.573-3.518 0-5.819-.41-1.656-1.196-2.903-2.862-2.903zm-3.216 13.807a1.08 1.08 0 0 1 1.074 1.088c0 .604-.48 1.094-1.074 1.094-.592 0-1.075-.49-1.075-1.094 0-.601.483-1.088 1.075-1.088"],
    ["terraform","M1.44 0v7.575l6.561 3.79V3.787zm21.12 4.227l-6.561 3.791v7.574l6.56-3.787zM8.72 4.23v7.575l6.561 3.787V8.018zm0 8.405v7.575L15.28 24v-7.578z"],
    ["typescript","M1.125 0C.502 0 0 .502 0 1.125v21.75C0 23.498.502 24 1.125 24h21.75c.623 0 1.125-.502 1.125-1.125V1.125C24 .502 23.498 0 22.875 0zm17.363 9.75c.612 0 1.154.037 1.627.111a6.38 6.38 0 0 1 1.306.34v2.458a3.95 3.95 0 0 0-.643-.361 5.093 5.093 0 0 0-.717-.26 5.453 5.453 0 0 0-1.426-.2c-.3 0-.573.028-.819.086a2.1 2.1 0 0 0-.623.242c-.17.104-.3.229-.393.374a.888.888 0 0 0-.14.49c0 .196.053.373.156.529.104.156.252.304.443.444s.423.276.696.41c.273.135.582.274.926.416.47.197.892.407 1.266.628.374.222.695.473.963.753.268.279.472.598.614.957.142.359.214.776.214 1.253 0 .657-.125 1.21-.373 1.656a3.033 3.033 0 0 1-1.012 1.085 4.38 4.38 0 0 1-1.487.596c-.566.12-1.163.18-1.79.18a9.916 9.916 0 0 1-1.84-.164 5.544 5.544 0 0 1-1.512-.493v-2.63a5.033 5.033 0 0 0 3.237 1.2c.333 0 .624-.03.872-.09.249-.06.456-.144.623-.25.166-.108.29-.234.373-.38a1.023 1.023 0 0 0-.074-1.089 2.12 2.12 0 0 0-.537-.5 5.597 5.597 0 0 0-.807-.444 27.72 27.72 0 0 0-1.007-.436c-.918-.383-1.602-.852-2.053-1.405-.45-.553-.676-1.222-.676-2.005 0-.614.123-1.141.369-1.582.246-.441.58-.804 1.004-1.089a4.494 4.494 0 0 1 1.47-.629 7.536 7.536 0 0 1 1.77-.201zm-15.113.188h9.563v2.166H9.506v9.646H6.789v-9.646H3.375z"],
    ["swift","M13.543 3.41c4.114 2.47 6.545 7.162 5.549 11.131-.024.093-.05.181-.076.272l.002.001c2.062 2.538 1.5 5.258 1.236 4.745-1.072-2.086-3.066-1.568-4.088-1.043a6.803 6.803 0 0 1-.281.158l-.02.012-.002.002c-2.115 1.123-4.957 1.205-7.812-.022a12.568 12.568 0 0 1-5.64-4.838c.649.48 1.35.902 2.097 1.252 3.019 1.414 6.051 1.311 8.197-.002C9.651 12.73 7.101 9.67 5.146 7.191a10.628 10.628 0 0 1-1.005-1.384c2.34 2.142 6.038 4.83 7.365 5.576C8.69 8.408 6.208 4.743 6.324 4.86c4.436 4.47 8.528 6.996 8.528 6.996.154.085.27.154.36.213.085-.215.16-.437.224-.668.708-2.588-.09-5.548-1.893-7.992z"],
    ["rust","M23.8346 11.7033l-1.0073-.6236a13.7268 13.7268 0 00-.0283-.2936l.8656-.8069a.3483.3483 0 00-.1154-.578l-1.1066-.414a8.4958 8.4958 0 00-.087-.2856l.6904-.9587a.3462.3462 0 00-.2257-.5446l-1.1663-.1894a9.3574 9.3574 0 00-.1407-.2622l.49-1.0761a.3437.3437 0 00-.0274-.3361.3486.3486 0 00-.3006-.154l-1.1845.0416a6.7444 6.7444 0 00-.1873-.2268l.2723-1.153a.3472.3472 0 00-.417-.4172l-1.1532.2724a14.0183 14.0183 0 00-.2278-.1873l.0415-1.1845a.3442.3442 0 00-.49-.328l-1.076.491c-.0872-.0476-.1742-.0952-.2623-.1407l-.1903-1.1673A.3483.3483 0 0016.256.955l-.9597.6905a8.4867 8.4867 0 00-.2855-.086l-.414-1.1066a.3483.3483 0 00-.5781-.1154l-.8069.8666a9.2936 9.2936 0 00-.2936-.0284L12.2946.1683a.3462.3462 0 00-.5892 0l-.6236 1.0073a13.7383 13.7383 0 00-.2936.0284L9.9803.3374a.3462.3462 0 00-.578.1154l-.4141 1.1065c-.0962.0274-.1903.0567-.2855.086L7.744.955a.3483.3483 0 00-.5447.2258L7.009 2.348a9.3574 9.3574 0 00-.2622.1407l-1.0762-.491a.3462.3462 0 00-.49.328l.0416 1.1845a7.9826 7.9826 0 00-.2278.1873L3.8413 3.425a.3472.3472 0 00-.4171.4171l.2713 1.1531c-.0628.075-.1255.1509-.1863.2268l-1.1845-.0415a.3462.3462 0 00-.328.49l.491 1.0761a9.167 9.167 0 00-.1407.2622l-1.1662.1894a.3483.3483 0 00-.2258.5446l.6904.9587a13.303 13.303 0 00-.087.2855l-1.1065.414a.3483.3483 0 00-.1155.5781l.8656.807a9.2936 9.2936 0 00-.0283.2935l-1.0073.6236a.3442.3442 0 000 .5892l1.0073.6236c.008.0982.0182.1964.0283.2936l-.8656.8079a.3462.3462 0 00.1155.578l1.1065.4141c.0273.0962.0567.1914.087.2855l-.6904.9587a.3452.3452 0 00.2268.5447l1.1662.1893c.0456.088.0922.1751.1408.2622l-.491 1.0762a.3462.3462 0 00.328.49l1.1834-.0415c.0618.0769.1235.1528.1873.2277l-.2713 1.1541a.3462.3462 0 00.4171.4161l1.153-.2713c.075.0638.151.1255.2279.1863l-.0415 1.1845a.3442.3442 0 00.49.327l1.0761-.49c.087.0486.1741.0951.2622.1407l.1903 1.1662a.3483.3483 0 00.5447.2268l.9587-.6904a9.299 9.299 0 00.2855.087l.414 1.1066a.3452.3452 0 00.5781.1154l.8079-.8656c.0972.0111.1954.0203.2936.0294l.6236 1.0073a.3472.3472 0 00.5892 0l.6236-1.0073c.0982-.0091.1964-.0183.2936-.0294l.8069.8656a.3483.3483 0 00.578-.1154l.4141-1.1066a8.4626 8.4626 0 00.2855-.087l.9587.6904a.3452.3452 0 00.5447-.2268l.1903-1.1662c.088-.0456.1751-.0931.2622-.1407l1.0762.49a.3472.3472 0 00.49-.327l-.0415-1.1845a6.7267 6.7267 0 00.2267-.1863l1.1531.2713a.3472.3472 0 00.4171-.416l-.2713-1.1542c.0628-.0749.1255-.1508.1863-.2278l1.1845.0415a.3442.3442 0 00.328-.49l-.49-1.076c.0475-.0872.0951-.1742.1407-.2623l1.1662-.1893a.3483.3483 0 00.2258-.5447l-.6904-.9587.087-.2855 1.1066-.414a.3462.3462 0 00.1154-.5781l-.8656-.8079c.0101-.0972.0202-.1954.0283-.2936l1.0073-.6236a.3442.3442 0 000-.5892zm-6.7413 8.3551a.7138.7138 0 01.2986-1.396.714.714 0 11-.2997 1.396zm-.3422-2.3142a.649.649 0 00-.7715.5l-.3573 1.6685c-1.1035.501-2.3285.7795-3.6193.7795a8.7368 8.7368 0 01-3.6951-.814l-.3574-1.6684a.648.648 0 00-.7714-.499l-1.473.3158a8.7216 8.7216 0 01-.7613-.898h7.1676c.081 0 .1356-.0141.1356-.088v-2.536c0-.074-.0536-.0881-.1356-.0881h-2.0966v-1.6077h2.2677c.2065 0 1.1065.0587 1.394 1.2088.0901.3533.2875 1.5044.4232 1.8729.1346.413.6833 1.2381 1.2685 1.2381h3.5716a.7492.7492 0 00.1296-.0131 8.7874 8.7874 0 01-.8119.9526zM6.8369 20.024a.714.714 0 11-.2997-1.396.714.714 0 01.2997 1.396zM4.1177 8.9972a.7137.7137 0 11-1.304.5791.7137.7137 0 011.304-.579zm-.8352 1.9813l1.5347-.6824a.65.65 0 00.33-.8585l-.3158-.7147h1.2432v5.6025H3.5669a8.7753 8.7753 0 01-.2834-3.348zm6.7343-.5437V8.7836h2.9601c.153 0 1.0792.1772 1.0792.8697 0 .575-.7107.7815-1.2948.7815zm10.7574 1.4862c0 .2187-.008.4363-.0243.651h-.9c-.09 0-.1265.0586-.1265.1477v.413c0 .973-.5487 1.1846-1.0296 1.2382-.4576.0517-.9648-.1913-1.0275-.4717-.2704-1.5186-.7198-1.8436-1.4305-2.4034.8817-.5599 1.799-1.386 1.799-2.4915 0-1.1936-.819-1.9458-1.3769-2.3153-.7825-.5163-1.6491-.6195-1.883-.6195H5.4682a8.7651 8.7651 0 014.907-2.7699l1.0974 1.151a.648.648 0 00.9182.0213l1.227-1.1743a8.7753 8.7753 0 016.0044 4.2762l-.8403 1.8982a.652.652 0 00.33.8585l1.6178.7188c.0283.2875.0425.577.0425.8717zm-9.3006-9.5993a.7128.7128 0 11.984 1.0316.7137.7137 0 01-.984-1.0316zm8.3389 6.71a.7107.7107 0 01.9395-.3625.7137.7137 0 11-.9405.3635z"]
  ]);
  const swiftTilePath = "M7.508 0c-.287 0-.573 0-.86.002-.241.002-.483.003-.724.01-.132.003-.263.009-.395.015A9.154 9.154 0 0 0 4.348.15 5.492 5.492 0 0 0 2.85.645 5.04 5.04 0 0 0 .645 2.848c-.245.48-.4.972-.495 1.5-.093.52-.122 1.05-.136 1.576a35.2 35.2 0 0 0-.012.724C0 6.935 0 7.221 0 7.508v8.984c0 .287 0 .575.002.862.002.24.005.481.012.722.014.526.043 1.057.136 1.576.095.528.25 1.02.495 1.5a5.03 5.03 0 0 0 2.205 2.203c.48.244.97.4 1.498.495.52.093 1.05.124 1.576.138.241.007.483.009.724.01.287.002.573.002.86.002h8.984c.287 0 .573 0 .86-.002.241-.001.483-.003.724-.01a10.523 10.523 0 0 0 1.578-.138 5.322 5.322 0 0 0 1.498-.495 5.035 5.035 0 0 0 2.203-2.203c.245-.48.4-.972.495-1.5.093-.52.124-1.05.138-1.576.007-.241.009-.481.01-.722.002-.287.002-.575.002-.862V7.508c0-.287 0-.573-.002-.86a33.662 33.662 0 0 0-.01-.724 10.5 10.5 0 0 0-.138-1.576 5.328 5.328 0 0 0-.495-1.5A5.039 5.039 0 0 0 21.152.645 5.32 5.32 0 0 0 19.654.15a10.493 10.493 0 0 0-1.578-.138 34.98 34.98 0 0 0-.722-.01C17.067 0 16.779 0 16.492 0H7.508z";
  const cardSize = ArchitectureLayout.card;
  const frameGeometry = ArchitectureLayout.frame;
  const measuring = document.createElement('canvas').getContext('2d');
  const systemFont = '-apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif';
  const monoFont = 'Menlo, monospace';
  const xml = value => String(value).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g,'�').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
  const singleLine = value => String(value||'').replace(/\s+/g,' ').trim();
  function fitText(value,width,font,tail=false){
    // Measure only a bounded prefix/suffix; full values remain available in List and Inspector.
    const original=singleLine(value).toWellFormed(),points=Array.from((tail?original.slice(-2048):original.slice(0,2048)).toWellFormed());
    measuring.font=font;
    if(original.length<=2048&&measuring.measureText(original).width<=width)return original;
    let low=0,high=points.length;
    while(low<high){const mid=Math.ceil((low+high)/2),candidate=tail?'…'+points.slice(-mid).join(''):points.slice(0,mid).join('')+'…';if(measuring.measureText(candidate).width<=width)low=mid;else high=mid-1;}
    return tail?'…'+points.slice(points.length-low).join(''):points.slice(0,low).join('')+'…';
  }
  function nodeContext(node,parents,nodes){
    const owner=nodes.get(node.attributes?.['cfg.functionID'])||nodes.get(parents.get(node.id));
    const source=node.anchor?.path||node.attributes?.['project.manifest'];
    const synthetic=node.kind==='basicBlock'&&node.attributes?.['cfg.synthetic']===true;
    const signature=typeof node.attributes?.['syntax.signature']==='string'?node.attributes['syntax.signature']:'';
    return {owner,source:typeof source==='string'?source:'',synthetic,detail:node.attributes?.['context.purpose']||signature||(owner?'in '+owner.name:synthetic?'Generated control-flow boundary':''),signature};
  }
  const accessoryOffset=42,accessoryY=14;
  function nodeAccessories(id){
    return external?.modelView===view&&!view?.canvas?external?.nodeAccessories?.get(id):undefined;
  }
  function accessoryArt(items,width,color){
    if(!items?.length)return '';
    const one=items.length===1?items[0]:null;
    const token={positive:'role-struct',negative:'role-actor',accent:'role-class'}[one?.tone]||'node-secondary';
    const icons={info:'M0 -5v1 M0 -1v6',flag:'M-4 6V-6l8 2-8 3',bookmark:'M-4 6V-6h8V6L0 3z'};
    const path=icons[one?.icon];
    const mark=path?('<path d="'+path+'" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>'):
      ('<text text-anchor="middle" dominant-baseline="central" fill="currentColor" font-family="'+systemFont+'" font-weight="650" font-size="14">'+xml(one?one.symbol:String(items.length))+'</text>');
    return '<g data-node-accessory="headerTrailing" transform="translate('+(width-accessoryOffset)+' '+accessoryY+')" color="'+color(token)+'">'+mark+'</g>';
  }
  function propertyRow(node,width=ArchitectureLayout.member.width,group=false){
    const height=group?frameGeometry.headerHeight:ArchitectureLayout.member.height,style=getComputedStyle(document.documentElement),color=key=>style.getPropertyValue(key).trim(),attributes=node.attributes||{};
    const recorded=key=>typeof attributes[key]==='string'?attributes[key]:undefined;
    const access=recorded('declaration.access'),setter=recorded('declaration.setterAccess'),binding=recorded('declaration.binding'),type=recorded('declaration.type');
    const label=(value,x,space,tint,weight=400)=>`<text x="${x}" y="21" font-family="${monoFont}" font-size="14" font-weight="${weight}" fill="${tint}">${xml(fitText(value,space,`${weight} 14px ${monoFont}`))}</text>`;
    const accessLabel=[access||'implicit',setter?setter+'(set)':''].filter(Boolean).join(' / ');
    const known=access||setter||binding||type;
    const summary=known?[accessLabel,binding||'—',node.name+':',type||'type not recorded'].join(' '):recorded('syntax.signature')||node.name+' : metadata not recorded';
    const items=nodeAccessories(node.id),reserved=items?.length?20:0;
    const content=group?label(summary,12,width-44-reserved,color('--graph-node-text'),600):known?label(accessLabel,12,160,color('--graph-node-secondary'))+label(binding||'—',184,60,color('--syntax-keyword'))+label(node.name,254,154,color('--graph-node-text'),600)+label(type?': '+type:': type not recorded',416,width-450-reserved,type?color('--syntax-type'):color('--graph-node-secondary')):label(recorded('syntax.signature')||node.name+' : metadata not recorded',12,width-44-reserved,color('--graph-node-text'));
    return 'data:image/svg+xml;utf8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><g data-presentation="${group?'property-frame':'property-row'}">${group?`<path d="M0 0H${width}V${height}H0Z" fill="${color('--graph-node-header')}"/>`:''}${content}${accessoryArt(items,width,key=>color('--graph-'+key))}<path d="M0 ${height-.5}H${width}" stroke="${color('--graph-node-divider')}"/></g></svg>`);
  }
  function svgLanguageMark(node,x,y,color){
    const key=languageKey(node);
    if(!key)return '';
    const name=languageName(node),path=languagePaths.get(key);
    const tint=path?color('language-'+key):color('node-secondary');
    let artwork;
    if(key==='swift'){
      artwork=`<path data-logo-part="background" d="${swiftTilePath}" fill="${tint}"/><path data-logo-part="bird" d="${path}" fill="#ffffff"/>`;
    }else if(key==='typescript'||key==='javascript'){
      const ts=key==='typescript';
      artwork=`<rect x="1" y="1" width="22" height="22" fill="${ts?'#ffffff':'#202020'}"/><path data-logo-part="symbol" d="${path}" fill="${ts?'#3178c6':'#f7df1e'}"/><rect x=".5" y=".5" width="23" height="23" rx="${ts?1:0}" fill="none" stroke="${tint}"/>`;
    }else if(path){
      artwork=`<path data-logo-part="symbol" d="${path}"/>`;
    }else{
      const initials=Array.from(name).slice(0,2).join('').toUpperCase();
      artwork=`<rect x="1" y="1" width="22" height="22" rx="4" fill="none" stroke="${tint}"/><text data-logo-part="monogram" x="12" y="12" text-anchor="middle" dominant-baseline="central" font-family="${monoFont}" font-weight="600" font-size="12">${xml(initials)}</text>`;
    }
    return `<g data-language="${xml(key)}" transform="translate(${x} ${y}) scale(.75)" fill="${tint}" role="img" aria-label="${xml(name)}"><title>${xml(name)}</title>${artwork}</g>`;
  }
  function svgRoleMark(node,accent,x=10,y=6){
    return `<g data-role="${symbolRole(node)}" transform="translate(${x} ${y})"><rect x=".5" y=".5" width="19" height="19" rx="4" fill="${accent}" fill-opacity=".14" stroke="${accent}"/><text x="10" y="10" text-anchor="middle" dominant-baseline="central" font-family="${monoFont}" font-size="11" font-weight="600" fill="${accent}">${xml(symbolKind(node)[1])}</text></g>`;
  }
  function callableNode(node,context,width=ArchitectureLayout.callable.width,group=false){
    const height=ArchitectureLayout.callable.height,style=getComputedStyle(document.documentElement),color=key=>style.getPropertyValue(key).trim(),attributes=node.attributes||{};
    const recorded=key=>typeof attributes[key]==='string'?attributes[key]:undefined;
    const structured=attributes['declaration.callable']?.version===1?attributes['declaration.callable']:undefined;
    const strings=value=>Array.isArray(value)?value.filter(v=>typeof v==='string'):[];
    const parameters=Array.isArray(structured?.parameters)?'('+structured.parameters.map(p=>p.spelling).filter(v=>typeof v==='string').join(', ')+')':recorded('declaration.parameters');
    const results=structured?.resultStatus==='recorded'?structured.results:undefined;
    const result=Array.isArray(results)?results.map(r=>r.type).filter(v=>typeof v==='string').join(', '):recorded('declaration.returnType');
    const modifiers=structured?[...strings(structured.modifiers),...strings(structured.effects),...strings(structured.safety)]:Array.isArray(attributes['declaration.modifiers'])?strings(attributes['declaration.modifiers']):undefined,access=structured?.access||recorded('declaration.access');
    const role=symbolRole(node),special=role==='initializer'?'Initializer':role==='deinitializer'?'Deinitializer':undefined,known=parameters!==undefined||result!==undefined||modifiers!==undefined;
    const generics=strings(structured?.typeParameters),receiver=structured?.receiver;
    const receiverText=typeof receiver?.spelling==='string'?receiver.spelling:receiver?.kind==='instance'?'self':receiver?.kind==='type'?'type member':'';
    const details=[receiverText,...strings(structured?.annotations)].filter(Boolean).join(' · '),constraints=strings(structured?.constraints).join(' · ');
    const label=(value,x,y,space,tint,size=12,weight=400)=>`<text x="${x}" y="${y}" font-family="${monoFont}" font-size="${size}" font-weight="${weight}" fill="${tint}">${xml(fitText(value,space,`${weight} ${size}px ${monoFont}`))}</text>`;
    const logo=svgLanguageMark(node,8,4,key=>color('--graph-'+key));
    const resultText=special||('→ '+(result||'not recorded'));
    const items=nodeAccessories(node.id),reserved=items?.length?20:0;
    const heading=svgRoleMark(node,color('--graph-role-'+roleToken(node)),logo?32:8,3)+label(symbolKind(node)[0],logo?59:36,17,width-(logo?59:36)-120-reserved,color('--graph-node-secondary'),10,600)+label(access||(known?'implicit':'—'),width-112-reserved,17,74,color('--syntax-keyword'),10)+logo;
    const content=label(node.name+(generics.length?'<'+generics.join(', ')+'>':''),12,45,width-24,color('--graph-node-text'),21,600)+label(parameters!==undefined?parameters:context.signature||'Parameters not recorded',12,63,width-24,color('--graph-node-secondary'),11)+label(details,12,78,width-24,color('--graph-node-secondary'),10.5)+label(constraints,12,93,width-24,color('--graph-node-secondary'),10.5)+label(resultText,12,110,width-24,result?color('--syntax-type'):color('--graph-node-secondary'),11.5)+label((modifiers||[]).join(' '),12,127,width-24,color('--syntax-keyword'),10.5);
    return 'data:image/svg+xml;utf8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><title>${xml(symbolKind(node)[0])}</title><g data-presentation="${group?'callable-frame':'callable-node'}"><path d="M0 0H${width}V${group?height:26}H0Z" fill="${color('--graph-node-header')}"/><path d="M0 26H${width}${group?`M0 ${height-.5}H${width}`:''}" stroke="${color('--graph-node-divider')}"/>${heading}${accessoryArt(items,width,key=>color('--graph-'+key))}${content}</g></svg>`);
  }

  function nodeCard(node,context,group=false,frameWidth=cardSize.width,frameHeight){
    if(node.canvas){
      const style=getComputedStyle(document.documentElement),color=key=>style.getPropertyValue('--graph-'+key).trim();
      const geometry=ArchitectureCanvasModel.size(node),width=group?frameWidth:geometry.width;
      const verdictInk={positive:'role-struct',negative:'role-actor',neutral:'node-secondary'}[node.proofCard?.tone];
      const accent=verdictInk||{condition:'role-method',result:'role-module',theorem:'role-struct',scope:'role-scope',counterexample:'edge-false'}[node.canvas.role];
      const language=svgLanguageMark(node,10,4,color);
      const marks={role:svgRoleMark(node,color('role-'+roleToken(node)),language?34:10,3),language};
      return ArchitectureCanvasModel.card(node,width,frameHeight??geometry.height,group,
        {text:color('node-text'),secondary:color('node-secondary'),header:color('node-header'),divider:color('node-divider'),accent:color(accent||'node-secondary')},
        (value,space,size,weight)=>fitText(value,space,`${weight} ${size}px ${systemFont}`),marks);
    }
    if(ArchitectureLayout.isCallable(node)&&!visibleLayout?.cfg)return callableNode(node,context,group?frameWidth:undefined,group);
    if(ArchitectureLayout.isProperty(node))return propertyRow(node,group?frameWidth:undefined,group);
    const width=group?frameWidth:cardSize.width;
    const style=getComputedStyle(document.documentElement),color=name=>style.getPropertyValue('--graph-'+name).trim();
    const [kind]=symbolKind(node),footer=context.source||'No source anchor';
    const label=(value,x,y,width,size,weight=400,mono=false,tail=false)=>`<text x="${x}" y="${y}" font-family="${mono?monoFont:systemFont}" font-size="${size}" font-weight="${weight}" fill="${color(weight===600?'node-text':'node-secondary')}">${xml(fitText(value,width,`${weight} ${size}px ${mono?monoFont:systemFont}`,tail))}</text>`;
    const role=context.synthetic?kind+' · Synthetic':kind,accent=color('role-'+roleToken(node));
    const languageMark=svgLanguageMark(node,10,7,color);
    const roleMark=svgRoleMark(node,accent,languageMark?34:10);
    const roleX=languageMark?62:38,items=nodeAccessories(node.id);
    const svg=`<?xml version="1.0" encoding="UTF-8"?><svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${group?frameGeometry.headerHeight:cardSize.height}"><defs><clipPath id="card"><rect width="${width}" height="112" rx="7"/></clipPath></defs><g clip-path="url(#card)"><path d="M0 0H${width}V${group?frameGeometry.headerHeight:32}H0Z" fill="${color('node-header')}"/><path d="M0 32H${width}M0 ${group?frameGeometry.headerHeight-.5:88}H${width}" stroke="${color('node-divider')}"/>${roleMark}${label(role,roleX,21,width-roleX-(items?.length?56:32),11,600)}${languageMark}${accessoryArt(items,width,color)}${label(nodeTitle(node),12,54,width-24,22,600)}${label(context.detail,12,75,width-24,10,400,!!context.signature)}${label(footer,12,103,width-24,10,400,false,true)}</g></svg>`;
    return 'data:image/svg+xml;utf8,'+encodeURIComponent(svg);
  }
  function cardData(node,parents,nodes,groups){
    const context=nodeContext(node,parents,nodes);
    return {id:node.id,kind:node.kind,...ArchitectureLayout.size(node,groups.has(node.id),visibleLayout.cfg),headerHeight:ArchitectureLayout.headerHeight(node,visibleLayout.cfg),canvasRole:node.canvas?.role||'',canvasDiagram:node.canvas?.diagram||'',canvasSVG:!!node.canvas?.svg,canvasTitle:node.name,presentation:!groups.has(node.id)&&ArchitectureLayout.isProperty(node)?'property-row':!groups.has(node.id)&&ArchitectureLayout.isCallable(node)&&!visibleLayout.cfg?'callable-node':'card',card:nodeCard(node,context,groups.has(node.id)),context};
  }
  const relationStyles = new Map([
    ['contains',{key:'contains',label:'Contains',token:'containment',line:'solid'}],
    ['dependsOn',{key:'dependencies',label:'Dependencies',token:'dependency',line:'solid'}],
    ['joinsNetwork',{key:'networks',label:'Network membership',token:'membership',line:'solid'}],
    ['mountsVolume',{key:'mounts',label:'Storage mounts',token:'reference',line:'solid'}],
    ['exports',{key:'exports',label:'Public exports',token:'membership',line:'solid'}],
    ['imports',{key:'dependencies',label:'Dependencies',token:'dependency',line:'solid'}],
    ['calls',{key:'calls',label:'Calls',token:'call',line:'solid'}],
    ['candidateCalls',{key:'candidate-calls',label:'Possible calls',token:'call',line:'dashed'}],
    ['candidateTypeReference',{key:'candidate-types',label:'Possible type references',token:'reference',line:'dashed'}],
    ['usesType',{key:'types',label:'Type references',token:'reference',line:'solid'}],
    ['references',{key:'references',label:'References',token:'reference',line:'dashed'}],
    ['memberOf',{key:'membership',label:'Design membership',token:'membership',line:'solid'}],
    ['controlFlow',{key:'flow',label:'Control flow',token:'flow',line:'solid'}],
    ['other',{key:'other',label:'Other',token:'other',line:'dotted'}]
  ]);
  const branchStyles = new Map([
    ['true',{key:'true',label:'True branch',token:'true',line:'solid'}],
    ['false',{key:'false',label:'False branch',token:'false',line:'dashed'}]
  ]);
  const allRelationStyles = Array.from(new Map([...relationStyles.values(),...branchStyles.values()].map(p=>[p.key,p])).values());
  function relationStyle(edge){
    const branch=edge.attributes?.['cfg.branch'];
    if(edge.kind==='controlFlow'&&branchStyles.has(branch))return branchStyles.get(branch);
    return relationStyles.get(edge.kind)||relationStyles.get('other');
  }
  const relationName = edge => edge.attributes?.['context.operation'] || (edge.kind==='candidateTypeReference'?'Possible type reference':'') || [edge.kind,edge.attributes?.['cfg.branch']].filter(Boolean).join(' / ');
  function relationSwatch(presentation){
    const swatch=text('span','','relation-swatch');swatch.setAttribute('aria-hidden','true');
    swatch.style.borderTopColor=getComputedStyle(document.documentElement).getPropertyValue('--graph-edge-'+presentation.token).trim();swatch.style.borderTopStyle=presentation.line;
    return swatch;
  }
  function renderEdgeLegend(){
    const legend=$('edge-legend');legend.replaceChildren();
    const present=new Map((visibleLayout?.edges||view.edges).map(edge=>{const p=relationStyle(edge);return [p.key,p];}));
    for(const p of allRelationStyles.filter(p=>present.has(p.key))) {const row=text('div','','edge-legend-item');row.setAttribute('role','listitem');row.append(relationSwatch(p),text('span',p.label+(p.key==='contains'&&visibleLayout?.hidden.size?(visibleLayout.cfg?' (function header)':visibleLayout.hidden.size===visibleLayout.containmentCount?' (frames)':' (frames / lines)'):'')));legend.append(row);}
    if(!present.size)legend.append(text('p','No relations in this view.'));
  }
  function graphStyle() {
    const style=getComputedStyle(document.documentElement);
    const color=name=>style.getPropertyValue('--graph-'+name).trim();
    return [
      {selector:'node',style:{shape:'round-rectangle','corner-radius':7,'background-color':color('node-fill'),'background-image':'data(card)','background-width':'100%','background-height':'100%','border-color':color('node-border'),'border-width':1,label:'',width:'data(width)',height:'data(height)'}},
      {selector:'node:parent',style:{'background-image':'data(card)','background-width':'100%','background-height':'data(headerHeight)','background-position-x':'0%','background-position-y':'0%','background-fit':'none','background-color':color('node-header'),'background-opacity':.35,'padding':frameGeometry.padding,'compound-sizing-wrt-labels':'exclude'}},
      {selector:'node[kind = "workspace"]',style:{'border-width':2}},
      {selector:'node[kind = "unresolvedSymbol"]',style:{'border-style':'dashed'}},
      {selector:'node:selected, node.reference-endpoint',style:{'border-width':3,'border-color':color('selected')}},
      {selector:'node[presentation = "property-row"]',style:{shape:'rectangle','corner-radius':0,'background-opacity':0,'border-width':0}},
      {selector:'node[presentation = "property-row"]:selected',style:{'border-width':0,'background-opacity':1,'background-color':style.getPropertyValue('--selection').trim()}},
      {selector:'edge',style:{width:1.2,opacity:.35,'arrow-scale':.7,'line-color':color('edge-other'),'target-arrow-color':color('edge-other'),'target-arrow-shape':'triangle','curve-style':'bezier',label:'','line-style':'dotted'}},
      ...allRelationStyles.map(p=>({selector:`edge[relation = "${p.key}"]`,style:{'line-color':color('edge-'+p.token),'target-arrow-color':color('edge-'+p.token),'line-style':p.line}})),
      {selector:'edge[relation = "candidate-types"]',style:{opacity:.78,width:1.6,'arrow-scale':.9}},
      {selector:'edge.routed',style:{'curve-style':'round-segments','segment-radii':8,'radius-type':'influence-radius','edge-distances':'node-position','segment-weights':'data(routeWeights)','segment-distances':'data(routeDistances)','source-endpoint':'data(routeStart)','target-endpoint':'data(routeEnd)'}},
      {selector:'edge.direct',style:{'curve-style':'straight','source-endpoint':'data(routeStart)','target-endpoint':'data(routeEnd)'}},
      {selector:'edge.context-muted',style:{opacity:.08}},
      {selector:'edge.context-focused',style:{width:1.8,opacity:1,'arrow-scale':.8}},
      {selector:'node[canvasRole = \"condition\"]',style:{shape:'diamond'}},
      {selector:'node[kind = \"canvasEvent\"],node[canvasRole = \"initial\"],node[canvasRole = \"final\"]',style:{shape:'ellipse'}},
      {selector:'node[canvasDiagram = "proofDependencies"][kind = "canvas"]',style:{shape:'round-rectangle'}},
      {selector:'node[?canvasSVG]',style:{'background-opacity':0,'border-width':0}},
      {selector:'node[kind = \"canvasLane\"]',style:{'background-height':'100%','background-opacity':0,'border-width':0}},
      {selector:'node[kind = \"canvasFragment\"]',style:{'background-image':'none','background-opacity':0,'border-width':1,'border-style':'dashed',label:'data(canvasTitle)','font-size':19,'text-valign':'top','text-halign':'center','text-margin-y':-5,color:color('node-secondary'),events:'no','z-compound-depth':'bottom'}},
      {selector:'edge[canvasLabel]',style:{label:'data(canvasLabel)',color:color('node-text'),opacity:.9,width:1.5,'font-size':12,'text-wrap':'wrap','text-max-width':200,'text-background-color':color('node-fill'),'text-background-opacity':1,'text-background-padding':3,'line-style':'solid'}},
      {selector:'edge[canvasDirected = 0]',style:{'target-arrow-shape':'none'}},
      {selector:'edge[canvasRole = \"reply\"]',style:{'line-style':'dashed'}},
      {selector:'edge[?canvasLoop]',style:{'curve-style':'bezier','loop-direction':'90deg','loop-sweep':'-50deg','control-point-step-size':edge=>Math.max(96,edge.source().outerWidth())}},
      {selector:'edge.hovered, edge:selected',style:{width:2,opacity:1,'arrow-scale':.8}}
    ];
  }
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change',()=>{if(cy){const nodes=new Map(view.nodes.map(n=>[n.id,n])),frames=cy.nodes(':parent').map(n=>({id:n.id(),x:n.position().x-frameWidth(n)/2,y:n.position().y-(n.height()+2*Number(n.numericStyle('padding')))/2,width:frameWidth(n),height:n.height()+2*Number(n.numericStyle('padding')),group:true}));cy.batch(()=>{cy.style(graphStyle());cy.nodes().forEach(n=>n.data('card',nodeCard(nodes.get(n.id()),n.data('context'),n.isParent(),frameWidth(n))));});try{applyFrameGeometry(frames);}catch(error){problem(error);}renderEdgeLegend();}});
  const frameWidth = node => node.width()+2*Number(node.numericStyle('padding'));
  function refreshFrameCards(frames=cy.nodes(':parent')){
    const nodes=new Map(view.nodes.map(node=>[node.id,node]));
    for(const element of frames){if(!element.isParent())continue;const image=nodeCard(nodes.get(element.id()),element.data('context'),true,frameWidth(element),element.height()+2*Number(element.numericStyle('padding')));if(element.data('card')!==image)element.data('card',image);}
  }
  function applyFrameGeometry(boxes){
    const frames=boxes.filter(box=>box.group).sort((a,b)=>cy.getElementById(b.id).ancestors().length-cy.getElementById(a.id).ancestors().length);
    cy.nodes(':parent').style({'min-width':0,'min-height':0});
    for(const box of frames){
      const element=cy.getElementById(box.id),children=element.children().boundingBox({includeLabels:false,includeOverlays:false}),padding=frameGeometry.padding;
      const left=children.x1-box.x-padding,right=box.x+box.width-padding-children.x2,top=children.y1-box.y-padding,bottom=box.y+box.height-padding-children.y2;
      if(Math.min(left,right,top,bottom)<-.01)throw Error('Layout frame does not contain its rendered children.');
      const horizontal=left+right,vertical=top+bottom;
      element.style({'min-width':box.width-2*padding,'min-height':box.height-2*padding,'min-width-bias-left':`${horizontal>0?100*left/horizontal:50}%`,'min-width-bias-right':`${horizontal>0?100*right/horizontal:50}%`,'min-height-bias-top':`${vertical>0?100*top/vertical:50}%`,'min-height-bias-bottom':`${vertical>0?100*bottom/vertical:50}%`});
    }
    refreshFrameCards();
  }
  function preserveFrameHeaders(frames){
    for(const element of frames.sort((a,b)=>b.ancestors().length-a.ancestors().length)){
      const children=element.children().boundingBox({includeLabels:false,includeOverlays:false}),height=Math.max(Number(element.numericStyle('min-height')),children.h+Number(element.data('headerHeight'))),space=height-children.h;
      const top=Math.min(1,Math.max(parseFloat(element.style('min-height-bias-top'))/100,Number(element.data('headerHeight'))/space));
      element.style({'min-height':height,'min-height-bias-top':`${100*top}%`,'min-height-bias-bottom':`${100*(1-top)}%`});
    }
    refreshFrameCards(frames);
  }
  function refreshEdgeFocus(){
    if(!cy)return;
    const hovered=edgeHoverNode?cy.getElementById(edgeHoverNode):cy.collection();
    const reference=cy.edges('[relation = "candidate-types"]:selected');
    const focus=hovered.length?hovered:cy.nodes(':selected'),scope=focus.union(focus.descendants());
    cy.batch(()=>{cy.edges().removeClass('context-muted context-focused');if(reference.length){cy.edges().addClass('context-muted');reference.removeClass('context-muted').addClass('context-focused');}else if(scope.length){cy.edges().addClass('context-muted');scope.connectedEdges().removeClass('context-muted').addClass('context-focused');}});
  }
  function clearEdgePreview(){
    const hovered=cy.edges('.hovered');
    if(!edgeHoverNode&&!hovered.length)return;
    edgeHoverNode=undefined;hovered.removeClass('hovered');refreshEdgeFocus();$('graph').title='';
  }
  function fitFormalGraph(){
    fitCanvas(40);
    const kind=view.canvas.metadata?.providerMetadata?.formalKind;
    if(cy.zoom()>=0.4||!kind||kind==='verificationCondition')return;
    const root=view.nodes.find(n=>n.canvas?.details?.attributes?.isDeclaredRoot);
    if(!root)return;
    const start=cy.getElementById(root.id),origin=start.position();
    let nearest,distance=Infinity;
    for(const edge of start.connectedEdges()){
      const other=edge.source().id()===root.id?edge.target():edge.source();
      if(other.id()===root.id)continue;
      const point=other.position(),length=Math.hypot(point.x-origin.x,point.y-origin.y);
      if(length<distance){nearest=other;distance=length;}
    }
    const targets=nearest?start.union(nearest):start;
    cy.fit(targets,24);
    cy.zoom(Math.min(1,Math.max(0.55,cy.zoom())));cy.center(targets);
  }
  function fitCanvas(padding=75){cy.fit(undefined,padding);if(cy.zoom()>1){cy.zoom(1);cy.center();}}
  function openCanvas(){
    if(!cy.nodes().length)return;
    fitCanvas(40);
    if(cy.zoom()<.75&&view.edges.some(edge=>edge.kind==='candidateTypeReference')){
      const references=cy.edges('[relation = "candidate-types"]');
      const degree=new Map();
      for(const edge of references)for(const node of [edge.source(),edge.target()])degree.set(node.id(),(degree.get(node.id())||0)+1);
      const hub=Array.from(degree.keys()).sort((a,b)=>degree.get(b)-degree.get(a)||a.localeCompare(b))[0];
      if(hub){
        const center=cy.getElementById(hub);
        const distance=n=>Math.hypot(n.position().x-center.position().x,n.position().y-center.position().y);
        const neighbors=center.neighborhood('node').toArray().sort((a,b)=>distance(a)-distance(b)||a.id().localeCompare(b.id()));
        cy.zoom(.75);cy.center(neighbors.length?center.union(neighbors[0]):center);return;
      }
    }
    if(cy.zoom()<.75){const scopes=cy.nodes(':parent').filter(n=>n.data('kind')==='package').sort((a,b)=>b.descendants().length-a.descendants().length||a.id().localeCompare(b.id()));const bounds=(scopes.length?scopes[0]:cy.elements()).boundingBox();cy.zoom(.75);cy.pan({x:24-bounds.x1*.75,y:24-bounds.y1*.75});}
  }
  function applyRoutes(routes){
    for(const route of routes||[]){
      const edge=cy.getElementById(route.id);if(!edge.length||edge.source().isParent()||edge.target().isParent()||edge.source().id()===edge.target().id())continue;
      const a=edge.source().position(),b=edge.target().position(),dx=b.x-a.x,dy=b.y-a.y,length2=dx*dx+dy*dy;
      if(length2<1)continue;
      const points=route.points,start=points[0],end=points[points.length-1],weights=[],distances=[];
      for(const point of points.slice(1,-1)){weights.push(((point.x-a.x)*dx+(point.y-a.y)*dy)/length2);distances.push((dx*(point.y-a.y)-dy*(point.x-a.x))/Math.sqrt(length2));}
      edge.data({routeWeights:weights,routeDistances:distances,routeStart:`${start.x-a.x}px ${start.y-a.y}px`,routeEnd:`${end.x-b.x}px ${end.y-b.y}px`});edge.addClass(weights.length?'routed':'direct');
    }
  }
  async function rpc(method,params={}) {
    if(saved) throw Error('This saved snapshot includes only the exported view. Further source and hierarchy are not bundled.');
    const url='/api?method='+encodeURIComponent(method)+'&params='+encodeURIComponent(JSON.stringify(params));
    const response=await fetch(url,{credentials:'same-origin'});const value=await response.json();
    if(!response.ok||value.error)throw Error(value.error?.message||value.error||('HTTP '+response.status));return value;
  }
  async function readWorkspaceSpecification(snapshotID){
    const result=await rpc('workspace.specification',{snapshotID});
    if(result.snapshotID!==snapshotID)throw Error('Specification snapshot mismatch.');
    if(result.status==='missing')return result;
    if(result.status!=='available'||typeof result.path!=='string'||typeof result.text!=='string')throw Error('Specification data is unavailable.');
    return result;
  }
  const external = !repositoryMode && typeof window.ArchitectureExtensionUI === 'function' ? new window.ArchitectureExtensionUI({rpc,saved,view:()=>(navigation?.verification||view?.canvas)?sourceView:view,enterVerification,paint:destinationPaint,log:terminal.write,onVerificationStatus:message=>{if(navigation?.verification)$('footer-status').textContent=message;},leaveVerification:()=>window.history.back(),selection:()=>selected,onPublicationsChanged:refreshWorkspaceModels,onCanvas:(data,publication,id,active,resolve)=>canvas.contribution(data,publication,id,active,resolve),onNavigate:(id,snapshotID)=>go({method:'graph.neighbors',focus:id,snapshotID,depth:0})}) : null;
  const headerMenus=new Map();
  let pickerAnchor,pickerPoint,headerFrame;
  function closePicker(){
    if(pickerAnchor){$('canvas-picker').hidePopover();pickerAnchor.removeAttribute('aria-expanded');pickerAnchor=undefined;}
  }
  function sourceCommands(entity){
    const verification=c4Map?.reports?.some(entry=>entry.binding.entityID===entity.id)?
      [['Open verification report','proofDependencies',()=>openMapVerification(entity)]]:[];
    if(entity.kind==='softwareSystem')return [['Open containers','expand',()=>expand(entity)],['Focus system','focus',()=>focusSystem(entity)],...verification];
    if(entity.attributes?.['context.owner'])return [entity.attributes['context.entryID']?['Open components','expand',()=>expand(entity)]:['Inspect container','focus',()=>inspect(entity)],...verification];
    const pinned=query.snapshotID?{snapshotID:query.snapshotID}:{};
    const commands=[
      ['Expand','expand',()=>expand(entity)],
      ['Neighbors','neighbors',()=>go({method:'graph.neighbors',focus:entity.id,depth:2,direction:$('direction').value,...pinned})],
      ['Impact','impact',()=>go({method:'graph.impact',focus:entity.id,depth:2,...pinned})]
    ];
    if(['function','method'].includes(entity.kind))commands.push(['Control flow','controlFlow',()=>go({method:'graph.cfg',focus:entity.id,depth:2,...pinned})]);
    return commands.concat(verification);
  }
  let propertySession;
  const propertyRequests=new Map();
  async function loadHostContext(){
    const session=await rpc('host.context');
    if(typeof session.workspaceRoot==='string'&&session.workspaceRoot){
      const path=$('workspace-root-path');
      path.textContent=session.workspaceRoot;
      path.title=session.workspaceRoot;
      path.hidden=false;
    }
    await enablePropertyAction(session);
  }
  async function enablePropertyAction(session){
    if(typeof document.modelContext?.registerTool!=='function'||typeof document.oai?.annotation?.request!=='function')return;
    if(!session.propertyActions)return;
    async function connect(threadID){
      const response=await fetch('/properties',{method:'POST',credentials:'same-origin',
        headers:{'Content-Type':'application/json','Authorization':'Bearer '+session.csrf},
        body:JSON.stringify({connect:true,threadID})});
      if(!response.ok)throw Error('This conversation does not own the property session.');
      propertySession={csrf:session.csrf,threadID};
      sessionStorage.setItem('architecture.propertyThread',threadID);
      return {connected:true};
    }
    await document.modelContext.registerTool({
      name:'connect_verification_actions',
      description:'Enable node property requests in this built-in browser tab for its launching Codex conversation. Supply the current thread ID.',
      inputSchema:{type:'object',properties:{threadID:{type:'string'}},required:['threadID'],additionalProperties:false},
      execute:async({threadID})=>connect(threadID)
    });
    await document.modelContext.registerTool({
      name:'read_verification_request',
      description:'Read the pinned node from the submitted browser annotation. Supply its requestID and the current Codex thread ID for every page, starting at page 0. Join chunks in page order and parse the JSON to recover exact files and relationships.',
      inputSchema:{type:'object',properties:{threadID:{type:'string'},page:{type:'integer',minimum:0},requestID:{type:'string'}},required:['threadID','page','requestID'],additionalProperties:false},
      annotations:{readOnlyHint:true},
      execute:async({threadID,page,requestID})=>{
        if(!propertySession||threadID!==propertySession.threadID)throw Error('This tab belongs to another conversation.');
        const request=propertyRequests.get(requestID);
        if(!request)throw Error('This request expired in this tab. Select the original node and submit a new annotation.');
        const pages=await request.pages;
        if(!Number.isSafeInteger(page)||page<0||page>=pages.length)throw Error('Page outside the selected request.');
        return {requestID:request.id,page,pageCount:pages.length,chunk:pages[page]};
      }
    });
    const previous=sessionStorage.getItem('architecture.propertyThread');
    if(previous)await connect(previous).catch(()=>sessionStorage.removeItem('architecture.propertyThread'));
  }
  function annotationRetry(message,retry){
    const dialog=text('dialog','','extension-panel property-analysis');
    dialog.setAttribute('aria-label','Define verification conditions');
    const header=text('div','','extension-heading');
    const close=button('×',()=>dialog.close());
    close.className='verification-close';
    close.setAttribute('aria-label','Close');
    close.title='Close';
    header.append(text('h2','Define verification conditions'),close);
    const content=text('div','','extension-content');
    content.append(text('p',message),button('Open annotation',()=>{dialog.close();retry();}));
    dialog.append(header,content);
    dialog.addEventListener('close',()=>dialog.remove(),{once:true});
    document.body.append(dialog);
    dialog.showModal();
  }
  function requestFormalVerification(anchor,node,snapshotID,workspaceID){
    const id=crypto.randomUUID();
    const prompt=subject=>'$formal-verification — Define verification conditions for '+subject+'. Read all read_verification_request pages. Save the spec and rationale in the target repo. Definition only. requestID '+id;
    const named=prompt('“'+node.name+'”');
    // The browser silently drops initial comments longer than 240 UTF-16 code units.
    const initialComment=named.length<=240?named:prompt('the selected node');
    const annotate=async()=>{
      try{
        const menu=headerMenus.get(node.id);
        if(!menu||menu.target!==anchor||view.snapshotID!==snapshotID||view.workspaceID!==workspaceID)
          throw Error('The selected node is no longer in this view.');
        positionHeaderMenu(node.id,menu);
        const result=await document.oai.annotation.request(anchor,{
          initialComment,
          metadata:{requestID:id,workspaceID,snapshotID,entityID:node.id},
          omitScreenshot:false
        });
        if(!result?.accepted)annotationRetry('Could not open the annotation.',annotate);
      }catch(error){annotationRetry('Could not open the annotation. '+error.message,annotate);}
    };
    // Anchor the editor to the source node while the click still has user activation.
    void annotate();
    const pages=(async()=>{
      const response=await fetch('/properties',{method:'POST',credentials:'same-origin',
        headers:{'Content-Type':'application/json','Authorization':'Bearer '+propertySession.csrf},
        body:JSON.stringify({workspaceID,snapshotID,entityID:node.id,threadID:propertySession.threadID})});
      const context=await response.json();
      if(!response.ok||context.error)throw Error(context.error||('HTTP '+response.status));
      if(context.entityID!==node.id||context.snapshotID!==snapshotID||context.workspaceID!==workspaceID)throw Error('Snapshot selection changed.');
      const payload=JSON.stringify(context),chunks=[];
      for(let offset=0;offset<payload.length;offset+=8192)chunks.push(payload.slice(offset,offset+8192));
      return chunks;
    })();
    if(propertyRequests.size>=4)propertyRequests.delete(propertyRequests.keys().next().value);
    propertyRequests.set(id,{id,pages});
    pages.catch(problem);
  }
  function openPicker(anchor,entity,nodeTarget,point){
    const picker=$('canvas-picker');
    if(!point&&pickerAnchor===anchor&&picker.matches(':popover-open')){closePicker();return;}
    closePicker();
    picker.replaceChildren();picker.setAttribute('aria-label',entity?'Actions for '+entity.name:'Published models');
    if(entity){
      inspect(entity);
      external.modelSlot(picker,{entity:entity.id,nodeMenu:true});
      const commands=text('div','','node-commands');
      addAccessoryCommands(commands,headerMenus.get(entity.id));
      for(const [label,icon,action] of sourceCommands(entity)){
        const command=button(label,()=>{closePicker();action();});
        command.dataset.icon=icon;commands.append(command);
      }
      if(propertySession){
        const {snapshotID,workspaceID}=view;
        const properties=button('Define verification conditions',()=>{closePicker();requestFormalVerification(nodeTarget,entity,snapshotID,workspaceID);});
        properties.dataset.icon='proofDependencies';commands.append(properties);
      }
      external.modelCommand(commands,entity,closePicker);
      picker.append(commands);
    }else external.modelSlot(picker,{});
    showPicker(picker,anchor,point);
  }
  function showPicker(picker,anchor,point){
    picker.ontoggle=()=>{if(pickerAnchor&&!picker.matches(':popover-open')){pickerAnchor.removeAttribute('aria-expanded');pickerAnchor=undefined;}};
    pickerAnchor=anchor;pickerPoint=point;anchor.setAttribute('aria-expanded','true');
    if(anchor.namespaceURI==='http://www.w3.org/2000/svg')picker.showPopover();
    else picker.showPopover({source:anchor});
    positionPicker();
    picker.querySelector('button')?.focus();
  }
  function positionPicker(){
    if(!pickerAnchor)return;
    const picker=$('canvas-picker'),anchor=pickerAnchor;
    const rect=anchor.getBoundingClientRect(),width=picker.offsetWidth,height=picker.offsetHeight;
    if(pickerPoint){
      const {x,y}=pickerPoint;
      const left=x+width<=window.innerWidth-6?x:x-width;
      const top=y+height<=window.innerHeight-6?y:y-height;
      picker.style.left=Math.max(6,left)+'px';picker.style.top=Math.max(6,top)+'px';
      picker.style.transformOrigin=(x-left)+'px '+(y-top)+'px';
      return;
    }
    const left=Math.max(6,Math.min(rect.right-width,window.innerWidth-width-6));
    const below=rect.bottom+height+10<=window.innerHeight;
    const top=below?rect.bottom+4:Math.max(6,rect.top-height-4);
    picker.style.left=left+'px';picker.style.top=top+'px';
    const originX=Math.max(0,Math.min(width,rect.left+rect.width/2-left));
    picker.style.transformOrigin=originX+'px '+(below?'top':'bottom');
  }
  function syncHeaderViewport(){
    if(!headerMenus.size)return;
    const pan=cy.pan();
    $('node-header-menus').style.transform='translate('+pan.x+'px,'+pan.y+'px) scale('+cy.zoom()+')';
  }
  function positionHeaderMenu(id,menu){
    const n=cy.getElementById(id);
    if(!n.length)return;
    const center=n.position(),width=n.outerWidth(),height=n.outerHeight();
    menu.target.style.width=width+'px';
    menu.target.style.height=height+'px';
    menu.target.style.transform='translate('+(center.x-width/2)+'px,'+(center.y-height/2)+'px)';
    menu.button.style.top=ArchitectureLayout.isCallable(menu.entity)&&!visibleLayout.cfg?'1px':'4px';
    if(menu.result)menu.result.style.top=menu.button.style.top;
  }
  function positionHeaderMenus(){
    headerFrame=undefined;
    for(const [id,menu] of headerMenus)positionHeaderMenu(id,menu);
    positionPicker();
  }
  function queueHeaders(){
    if(headerMenus.size&&headerFrame===undefined)headerFrame=requestAnimationFrame(positionHeaderMenus);
  }
  function accessoryCommand(menu,item){
    const source=view;
    const title=item.condition?item.backend+' · '+item.label+' · '+item.condition.name:item.label;
    const run=()=>{closePicker();return external.openNodeAccessory(menu.entity.id,item,()=>view===source).catch(problem);};
    return {title,run};
  }
  function addAccessoryCommands(host,menu){
    for(const item of menu?.accessories||[]){
      const {title,run}=accessoryCommand(menu,item);
      const option=button(title,run);
      option.dataset.icon=item.condition?'proofDependencies':'document';
      host.append(option);
    }
  }
  function tappedAccessory(event){
    const element=event.target,menu=headerMenus.get(element.id());
    if(!menu?.accessories?.length||!event.position)return false;
    const center=element.position(),x=center.x+element.outerWidth()/2-accessoryOffset;
    const y=center.y-element.outerHeight()/2+accessoryY;
    if(Math.abs(event.position.x-x)>10||Math.abs(event.position.y-y)>10)return false;
    if(menu.accessories.length===1)accessoryCommand(menu,menu.accessories[0]).run();
    else openPicker(menu.button,menu.entity,menu.target);
    return true;
  }
  function syncNodeAccessories(menu,items){
    if(menu.accessories===items)return;
    menu.accessories=items;
    if(items?.length){
      if(!menu.result){
        menu.result=button('',()=>{if(menu.accessories?.length===1)accessoryCommand(menu,menu.accessories[0]).run();else openPicker(menu.button,menu.entity,menu.target);},'node-result');
        menu.target.append(menu.result);
      }
      const title=items.length===1?accessoryCommand(menu,items[0]).title:items.length+' published results';
      menu.result.hidden=false;menu.result.title=title;menu.result.setAttribute('aria-label','Open '+title+' · '+menu.entity.name);
    }else if(menu.result)menu.result.hidden=true;
    const n=cy?.getElementById(menu.entity.id);
    if(!n?.length)return;
    n.data('card',nodeCard(menu.entity,n.data('context'),n.isParent(),frameWidth(n)));
  }
  function refreshWorkspaceModels(){
    const browse=$('workspace-models');
    if(pendingDestination){browse.hidden=true;return;}
    if(!browse||!external)return;
    const page=!view?.canvas&&view===external.modelView?external.modelPage:null;
    for(const [id,menu] of headerMenus)syncNodeAccessories(menu,page?external.nodeAccessories?.get(id):undefined);
    browse.hidden=!page||(!page.nextCursor&&external.menuItems(view,page).next().done);
    browse.onclick=()=>openPicker(browse);
    if(pickerAnchor===browse&&browse.hidden)closePicker();
  }
  function syncHeaderMenus(nodes){
    const layer=$('node-header-menus');
    if(!layer||!external||saved)return;
    const previous=new Set(headerMenus.keys());
    if(!view?.canvas)for(const entity of nodes){
      previous.delete(entity.id);
      let menu=headerMenus.get(entity.id);
      if(!menu){
        const target=document.createElement('div');
        target.setAttribute('role','group');
        target.dataset.nodeId=entity.id;
        menu={entity,target,button:button('•••',()=>openPicker(menu.button,menu.entity,target))};
        menu.button.setAttribute('aria-haspopup','dialog');
        target.append(menu.button);layer.append(target);headerMenus.set(entity.id,menu);
      }
      menu.entity=entity;
      menu.target.setAttribute('aria-label',nodeTitle(entity)+' · '+symbolKind(entity)[0]);
      menu.button.title='Actions for '+entity.name;
      menu.button.setAttribute('aria-label',menu.button.title);
    }
    for(const id of previous){headerMenus.get(id).target.remove();headerMenus.delete(id);}
    syncHeaderViewport();queueHeaders();
  }
  const canvas = !repositoryMode && typeof window.ArchitectureCanvasUI==='function'?new window.ArchitectureCanvasUI({saved,rpc,problem,refreshMapReports,graph:()=>cy,ready:()=>layoutReadyQuery===query,
    enter:(target,push,retry)=>{
      if($('model-info').matches(':popover-open'))$('model-info').hidePopover();
      if(!navigation.verification){
        const replace=!!navigation.loadingCanvas;
        if(push&&!replace){let origin=captureNavigation();if(c4Map)origin={...origin,query:{...origin.query,snapshotID:view.snapshotID}};cacheNavigation(origin);window.history.replaceState(origin,'');navigation={...origin,index:origin.index+1};}
        navigation={...navigation,loadingCanvas:target,canvasSessionID:target.id,camera:undefined,selection:undefined,fact:undefined};
        for(const key of canvasReaders.keys())if(key>navigation.index)canvasReaders.delete(key);
        canvasReaders.set(navigation.index,retry);if(canvasReaders.size>32)canvasReaders.delete(canvasReaders.keys().next().value);
        window.history[push&&!replace?'pushState':'replaceState'](navigation,'',location.pathname+(target.id?'#canvas='+encodeURIComponent(target.id):''));cacheNavigation(navigation);
      }
      $('back').disabled=navigation.index===0;
      $('level').hidden=true;$('diff').hidden=true;
      const token=beginDestination(target.title,target.detail||'Loading diagram…');
      return {token,paint:destinationPaint(),current:()=>token===destinationSerial};
    },
    error:(transition,error,retry)=>failDestination(transition?.token,error,retry),
    leave:()=>{external?.closeModel?.();if(navigation){delete navigation.canvasSessionID;delete navigation.loadingCanvas;window.history.replaceState(navigation,'',location.pathname);}beginDestination(routeTitle(query));load().catch(problem);},
    present:(session,push)=>{
      if(external?.review&&session.document.metadata?.publicationID!==external.review.publication?.publicationID)external.closeModel();
      const same=view?.queryID===session.viewSessionID;request++;inspection++;
      if(push&&!saved&&navigation){
        const replace=!!navigation.verification||!!navigation.loadingCanvas;
        if(!replace){
          navigation=captureNavigation();
          if(c4Map){navigation={...navigation,query:{...navigation.query,snapshotID:view.snapshotID}};cacheNavigation(navigation);}
          if(c4Map)window.history.replaceState(navigation,'',location.pathname);else window.history.replaceState(navigation,'');
        }
        navigation={...navigation,index:navigation.index+(replace?0:1),canvasSessionID:session.viewSessionID,camera:undefined,selection:undefined,fact:undefined};
        delete navigation.verification;delete navigation.loadingCanvas;
        window.history[replace?'replaceState':'pushState'](navigation,'',location.pathname+'#canvas='+encodeURIComponent(session.viewSessionID));
        cacheNavigation(navigation);$('back').disabled=false;
      }
      if(navigation?.loadingCanvas){delete navigation.loadingCanvas;navigation.canvasSessionID=session.viewSessionID;window.history.replaceState(navigation,'',location.pathname+'#canvas='+encodeURIComponent(session.viewSessionID));cacheNavigation(navigation);}
      if(external?.review){
        external.review.panel.dataset.presentation='graph';
        $('model-info').append(external.review.panel);
      }
      selectedFact=undefined;view=ArchitectureCanvasModel.view(session);hierarchy={nodes:[]};selected=undefined;render(same);
      if(!same)logGraph(view,'Opened '+session.document.title);
      applyCanvasState(session,same);
    },update:session=>applyCanvasState(session,true)}) : null;
  function applyCanvasState(session,same){
      const graph=cy;canvas.applying=true;
      const trace=$('trace-steps');
      if(trace){
        const steps=ArchitectureCanvasModel.traceOrder(session.document);
        trace.hidden=!steps.length;
        if(steps.length){
          const index=steps.indexOf(session.state.selection?.[0]);
          $('trace-position').textContent=index<0?'Counterexample':(index+1)+' / '+steps.length;
          const move=i=>{
            const ids=[steps[i]];
            canvas.command('canvas.select',{ids}).then(()=>{
              if(canvas.session?.viewSessionID===session.viewSessionID)return canvas.command('canvas.focus',{ids});
            }).catch(problem);
          };
          $('trace-prev').disabled=index<1;$('trace-prev').onclick=()=>move(index-1);
          $('trace-next').disabled=index===steps.length-1;$('trace-next').onclick=()=>move(index+1);
        }
      }
      try{
        if(same&&session.state.geometry?.length){graph.batch(()=>{for(const box of session.state.geometry){const node=graph.getElementById(box.id);if(node.length&&!node.isParent()){const x=box.x+box.width/2,y=box.y+box.height/2,current=node.position();if(Math.abs(current.x-x)>.000001||Math.abs(current.y-y)>.000001)node.position({x,y});}}});refreshFrameCards();}
        const wanted=[...(session.state.selection||[])].sort(),current=graph.$(':selected').map(n=>n.id()).sort();if(JSON.stringify(wanted)!==JSON.stringify(current)){graph.elements().unselect();for(const id of wanted)graph.getElementById(id).select();}
        if(session.state.camera){graph.zoom(session.state.camera.zoom);graph.pan(session.state.camera.pan);}
        if(layoutReadyQuery===query&&canvas.focusKey!==session.viewSessionID+':'+session.state.focusNonce){canvas.focusKey=session.viewSessionID+':'+session.state.focusNonce;if(session.state.focus?.length){let targets=graph.collection();for(const id of session.state.focus)targets=targets.union(graph.getElementById(id));if(targets.length){graph.fit(targets,70);queueMicrotask(()=>canvas.camera());}}}
        const id=session.state.selection?.[0];if(canvas.inspectionKey!==id){canvas.inspectionKey=id;const target=view.nodes.find(n=>n.id===id);if(target)inspect(target);else if(id)inspectCanvasEdge(id);else{selected=undefined;$('inspector').replaceChildren(text('h2','No Selection'),text('p','Select a diagram element to inspect its original data.'));}}
      }finally{canvas.applying=false;}
  }
  let hierarchy={nodes:[]};
  const navigationCache=new Map();
  const navigationMethods=new Set(['graph.overview','graph.children','graph.neighbors','graph.impact','graph.search','graph.cfg','workspace.specification']);
  function recognizedNavigation(state){return state?.architectureExplorer===1&&Number.isInteger(state.index)&&state.index>=0&&navigationMethods.has(state.query?.method);}
  function cacheNavigation(state){navigationCache.delete(state.index);navigationCache.set(state.index,state);if(navigationCache.size>32)navigationCache.delete(navigationCache.keys().next().value);}
  function enterVerification(source,entity,project=false){
    if(!navigation.verification){
      request++;
      const origin=captureNavigation();
      window.history.replaceState(origin,'');
      const {id,name,kind,language,anchor}=entity;
      const verification={workspaceID:source.workspaceID,snapshotID:source.snapshotID,entity:{id,name,kind,language,anchor},project};
      navigation={...origin,index:origin.index+1,verification};
      for(const key of navigationCache.keys())if(key>=navigation.index)navigationCache.delete(key);
      window.history.pushState(navigation,'',location.pathname);
      cacheNavigation(navigation);
    }
    const title=project?'Verify project':'Verify model';
    beginDestination(title,entity.name+' · Preparing verification…');
    $('back').disabled=false;
    $('view-title').textContent=title;
    $('breadcrumb').replaceChildren(text('span',title,'crumb-current'));
    external.review.panel.tabIndex=-1;
    external.review.panel.focus({preventScroll:true});
    // Let the destination paint before consuming even a cached result.
    return destinationPaint();
  }
  function restoreVerification(target){
    canvas?.leaveLocal();
    sourceView={workspaceID:target.workspaceID,snapshotID:target.snapshotID};
    return external.reviewModel(sourceView,target.entity,null,false,()=>{},target.project);
  }
  function captureNavigation(){
    if(!navigation)return;
    if(navigation.verification||navigation.loadingCanvas)return navigation;
    const ready=layoutReadyQuery===query;
    const state={...navigation,allFileDeclarations,query:{...query},list:!$('node-list').hidden,selection:ready?selected?.id:navigation.selection,fact:ready?selectedFact:navigation.fact,c4Camera:ready&&c4Map?{scale:c4Map.scale,cx:c4Map.cx,cy:c4Map.cy}:undefined,camera:ready&&cy&&!c4Map?{zoom:cy.zoom(),pan:{...cy.pan()}}:navigation.camera};
    cacheNavigation(state);return state;
  }
  function clearSelection(sync=true){
    if(sync&&canvas?.active&&!canvas.applying)canvas.selection([]);
    c4Map?.select(null);
    selected=undefined;selectedFact=undefined;inspection++;edgeHoverNode=undefined;
    if(cy){cy.elements().unselect();cy.nodes().removeClass('reference-endpoint');cy.edges().removeClass('hovered');refreshEdgeFocus();}
    for(const entry of document.querySelectorAll('[data-entity-id]')){entry.classList.toggle('active',false);entry.setAttribute('aria-pressed','false');}
    $('graph').title='';$('inspector').replaceChildren(text('h2','No Selection'),text('p','Select an entity to inspect its source and relations.'));
  }
  function scopeQuery(node){return node.kind==='designGroup'?{method:'graph.children',focus:node.id,depth:1}:{method:'graph.children',focus:node.id,level:'file',depth:['workspace','system','package','module'].includes(node.kind)?3:2};}
  function openScope(node){go({...scopeQuery(node),...(query.snapshotID?{snapshotID:query.snapshotID}:{})});}
  async function readHierarchy(next,route){
    if(['context','container'].includes(route.level)&&route.focus)return {nodes:next.nodes.filter(n=>n.id===route.focus)};
    if(!route.focus)return {nodes:[]};
    const fallback=next.nodes.find(n=>n.id===route.focus);
    try{
      const result=await rpc('graph.neighbors',{focus:route.focus,snapshotID:next.snapshotID,kinds:['contains'],direction:'incoming',depth:8,limit:500,edgeLimit:1500});
      if(result.snapshotID!==next.snapshotID)throw Error('Hierarchy snapshot mismatch.');
      if(!Array.isArray(result.nodes)||!Array.isArray(result.edges))throw Error('Hierarchy data is unavailable.');
      if(result.truncated)throw Error('Hierarchy exceeds its query budget.');
      const nodes=new Map(result.nodes.map(n=>[n.id,n])),focus=nodes.get(route.focus);
      if(!focus)throw Error('Current scope is unavailable in the hierarchy.');
      const recordedParents=new Map(),closure=new Map();
      for(const edge of result.edges)if(edge.kind==='contains'){if(!recordedParents.has(edge.target))recordedParents.set(edge.target,new Set());recordedParents.get(edge.target).add(edge.source);}
      // Bounded by the 500-node hierarchy response; discard only redundant ancestor shortcuts.
      function ancestorsOf(id){
        if(closure.has(id))return closure.get(id);
        const found=new Set(),pending=[id];
        while(pending.length){for(const parent of recordedParents.get(pending.pop())||[]){if(parent===id)throw Error('Invalid recorded containment hierarchy.');if(!found.has(parent)){found.add(parent);pending.push(parent);}}}
        closure.set(id,found);return found;
      }
      const path=[focus],seen=new Set([focus.id]);let current=focus;
      while(true){
        const candidates=[...(recordedParents.get(current.id)||[])],parents=candidates.filter(id=>!candidates.some(other=>other!==id&&ancestorsOf(other).has(id)));
        if(candidates.length&&!parents.length)throw Error('Invalid recorded containment hierarchy.');
        if(parents.length>1)return {nodes:path,issue:'Multiple recorded parents; the earlier hierarchy is ambiguous.'};
        if(!parents.length)break;
        const parent=nodes.get(parents[0]);if(!parent||seen.has(parent.id))throw Error('Invalid recorded containment hierarchy.');
        seen.add(parent.id);path.unshift(parent);current=parent;
      }
      return {nodes:path,...(path.length>=9&&path[0].kind!=='workspace'?{issue:'Earlier ancestors are outside the eight-level hierarchy view.'}:{})};
    }catch(error){return {nodes:fallback?[fallback]:[],issue:'Hierarchy unavailable: '+error.message};}
  }
  function renderBreadcrumbs(pending=false){
    const host=$('breadcrumb');host.replaceChildren();
    const home=button('',()=>go({method:'graph.overview',level:'context',...(query.snapshotID?{snapshotID:query.snapshotID}:{})}));home.className='crumb-home';home.setAttribute('aria-label','Workspace overview');home.title=hierarchy.nodes.find(n=>n.kind==='workspace')?.name||$('workspace').textContent||'Workspace';home.disabled=saved;home.innerHTML='<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m3 10 9-7 9 7M5 9v12h5v-7h4v7h5V9"/></svg>';host.append(home);
    if(view?.canvas&&!pending){
      const title=view.canvas.title||'Diagram',parts=title.split(' · ');
      const short=view.canvas.verification&&parts.length>1?parts[1]:title;
      const current=text('span',short,'crumb-current');current.title=title;
      host.append(text('span','›','crumb-separator'),current);$('view-title').textContent=title;return;
    }
    if(pending){host.append(text('span','Loading…','crumb-current'));$('view-title').textContent='Loading architecture';return;}
    const modes={'graph.cfg':'Control Flow','graph.neighbors':'Neighbors','graph.impact':'Impact'},mode=modes[query.method];
    const path=hierarchy.nodes.filter(n=>n.id!==view?.workspaceID),focus=hierarchy.nodes.at(-1);
    const ancestors=mode?path:path.slice(0,-1);
    const separator=()=>{const e=text('span','›','crumb-separator');e.setAttribute('aria-hidden','true');return e;};
    const c4Subject=view?.extensions?.['c4.container']?.subject||view?.extensions?.['c4.context']?.subject;
    const system=c4Subject&&view.nodes.find(node=>node.id===c4Subject);
    if(system){
      const domains=(system.attributes?.['context.areas']||[]).map(area=>area.name);
      const trail=[...domains,system.name].join(' › ');
      if(domains.length){
        const ancestry=text('span',domains.join(' › '),'crumb-domains');ancestry.title=trail;
        host.append(separator(),ancestry);
      }
      const current=text('span',system.name,'crumb-current');current.title=trail;current.setAttribute('aria-current','page');
      host.append(separator(),current);$('view-title').textContent=system.name;return;
    }
    if(hierarchy.issue){const notice=text('span','Hierarchy incomplete','crumb-notice');notice.title=hierarchy.issue;host.append(separator(),notice);}
    if(ancestors.length){
      const picker=document.createElement('select');picker.className='crumb-overflow';picker.setAttribute('aria-label','Jump to ancestor');picker.title='Jump to ancestor';
      const initial=text('option','…');initial.value='';picker.append(initial);
      for(const node of ancestors){const option=text('option',symbolKind(node)[0]+' · '+nodeTitle(node));option.value=node.id;picker.append(option);}
      picker.onchange=()=>{const node=ancestors.find(n=>n.id===picker.value);if(node)openScope(node);};host.append(picker);
      ancestors.forEach((node,index)=>{const item=text('span','','crumb-item '+(index===ancestors.length-1?'crumb-parent':'crumb-middle')),link=button(nodeTitle(node),()=>openScope(node));link.title=symbolKind(node)[0]+' · '+node.name;item.append(separator(),link);host.append(item);});
    }
    const label=saved?(view.extensions?.['c4.container']?'Containers · Saved snapshot':view.extensions?.['c4.context']?'System Context · Saved snapshot':'Saved snapshot'):mode||focus&&nodeTitle(focus)||(query.focus?'Current scope':query.method==='graph.search'?'Search Results':{context:'System Context',module:'Modules',component:'Types & Groups',function:'Functions & Methods',file:'Files',system:'System'}[query.level]||'Architecture');
    const current=text('span',label,'crumb-current');current.setAttribute('aria-current','page');current.title=focus&&!mode?focus.name:label;host.append(separator(),current);$('view-title').textContent=label;
  }
  function setListView(visible){
    $('node-list').hidden=!visible;
    const toggle=$('list-toggle');
    toggle.setAttribute('aria-pressed',String(visible));
    toggle.textContent=visible?($('c4-surface').hidden?'Graph view':'Map'):'List view';
  }
  function applyNavigation(state){
    clearTimeout(searchTimer);request++;layoutGeneration++;$('local-filter').value='';
    if(state.query.method==='graph.children'&&!state.query.level&&state.level==='module')state={...state,query:{...state.query,level:'file',depth:3},camera:undefined};
    allFileDeclarations=!!state.allFileDeclarations;navigation=state;query=state.query;clearSelection(false);hierarchy={nodes:[]};renderBreadcrumbs(true);
    $('level').value=state.level||query.level||'module';$('relation').value=query.kinds?.[0]||'';$('language').value=query.languages?.[0]||'';$('direction').value=query.direction||'outgoing';$('search').value=query.method==='graph.search'?query.text||'':'';
    setListView(!!state.list);$('back').disabled=state.index===0;
    const readingSpec=query.method==='workspace.specification'&&!state.canvasSessionID&&!state.loadingCanvas;
    $('level').hidden=readingSpec||!!(state.canvasSessionID||state.loadingCanvas||state.verification);$('diff').hidden=$('level').hidden;
    $('list-toggle').hidden=readingSpec;$('export').hidden=readingSpec;
    if(readingSpec){$('canvas-tools').hidden=true;$('model-info-toggle').hidden=true;}
    beginDestination(state.loadingCanvas?.title||state.title||routeTitle(query),query.snapshotID?'Snapshot '+query.snapshotID+' · Loading…':'Loading…');
  }
  function setupNavigation(){
    if(saved){$('back').disabled=true;return;}
    const current=window.history.state;
    applyNavigation(recognizedNavigation(current)?current:{architectureExplorer:1,index:0,query:{...query},level:'context',list:false});
    window.history.replaceState(navigation,'');
    window.addEventListener('popstate',event=>{
      if(!recognizedNavigation(event.state))return;
      external?.closeModel?.();
      captureNavigation();
      const state=navigationCache.get(event.state.index)||event.state;
      applyNavigation(state);
      if(state.verification)restoreVerification(state.verification).catch(problem);
      else if(state.canvasSessionID&&canvas)canvas.openSession(state.canvasSessionID).catch(problem);
      else if(state.loadingCanvas){canvas?.leaveLocal();const retry=canvasReaders.get(state.index);if(retry)retry();else failDestination(destinationSerial,Error('This pending diagram has no retained input. Return to the source and reopen it.'));}
      else{canvas?.leaveLocal();load().catch(problem);}
    });
  }
  function go(next,replace=false){
    external?.closeModel?.();
    const imported=canvas?.active||navigation?.loadingCanvas;canvas?.leaveLocal();
    clearTimeout(searchTimer);
    if(saved){problem(Error('This saved snapshot includes only the exported view. Further navigation is not bundled.'));return;}
    if(!navigation?.verification&&!imported&&JSON.stringify(query)===JSON.stringify(next))return;
    navigation=captureNavigation();window.history.replaceState(navigation,'');
    const index=navigation.index+(replace?0:1);
    if(replace)navigationCache.delete(index);
    else for(const key of navigationCache.keys())if(key>=index)navigationCache.delete(key);
    const target=view?.nodes.find(node=>node.id===next.focus);
    const state={architectureExplorer:1,index,query:{...next},level:next.level||navigation.level,list:navigation.list,title:target?target.name+' · '+routeTitle(next):routeTitle(next)};
    window.history[replace?'replaceState':'pushState'](state,'',location.pathname);applyNavigation(state);load().catch(problem);
  }
  async function load(refresh=false){
    if(navigation?.verification||navigation?.loadingCanvas||canvas?.active)return;
    if(pendingDestination&&$('empty').dataset.state==='failed')beginDestination(pendingDestination.title);
    const serial=++request,token=pendingDestination?.token;let next;
    try{
    if(pendingDestination)await destinationPaint();
    if(serial!==request)return;
    if(query.method==='workspace.specification'){
      const specification=await readWorkspaceSpecification(query.snapshotID);
      if(serial===request)renderSpecification(specification);
      return;
    }
    next=await rpc(query.method,query);
    if(serial!==request)return;
    if(!next.nodes)throw Error('The selected API did not return a graph view.');
    if(!saved&&query.method==='graph.overview'&&query.level==='context'&&!next.nodes.length){
      const {snapshotID}=query;
      go({method:'graph.overview',level:'module',...(snapshotID?{snapshotID}:{})},true);return;
    }
    const nextHierarchy=await readHierarchy(next,query);if(serial!==request)return;
    if(external?.review&&external.review.view.snapshotID!==next.snapshotID)external.closeModel();
    if(!refresh||view?.snapshotID!==next.snapshotID)logGraph(next,'Loaded '+query.method);
    hierarchy=nextHierarchy;const previous=view;view=next;sourceView=next;external?.refresh().catch(problem);render(refresh&&previous?.queryID===view.queryID);
    if(!selected&&(selectedFact||navigation?.fact)){const edge=view.edges.find(e=>e.id===(selectedFact||navigation.fact));if(edge)inspectSourceEdge(edge,true);else clearSelection(false);}
    if(!selected&&!selectedFact&&navigation?.selection)selected=view.nodes.find(n=>n.id===navigation.selection);
    if(selected){const node=view.nodes.find(n=>n.id===selected.id);if(node)inspect(node);else if(refresh){$('inspector').replaceChildren(text('h2','Selection changed'),text('p','This entity was deleted or moved outside the visible view. Use Back to return to its previous scope.'));}}
    }catch(error){if(serial!==request)return;if(token)failDestination(token,error,()=>load());else throw error;}
  }
  function renderSpecification(specification){
    finishDestination();$('empty').hidden=true;
    const reader=$('specification-reader'),missing=specification.status==='missing';
    const heading=text('h2',specification.path||'SPEC.md');heading.id='specification-file';
    reader.replaceChildren(heading,missing?text('p','No SPEC.md recorded in this workspace.'):text('pre',specification.text));
    reader.hidden=false;reader.scrollTop=0;
    $('counts').textContent=missing?'No specification':'Specification';$('scope-count').textContent='';
    $('snapshot-short').textContent=specification.snapshotID.slice(0,8);
    $('footer-status').textContent='Specification · Snapshot '+specification.snapshotID.slice(0,8);
  }
  function focusNavigatorNode(id){
    const element=cy.getElementById(id);
    if(!element.length)return;
    const box=element.renderedBoundingBox(),width=cy.width(),height=cy.height();
    if(box.x1<0||box.y1<0||box.x2>width||box.y2>height){
      const padding=24;
      cy.panBy({x:(width-box.w)/2-box.x1,y:Math.max(padding,(height-box.h)/2)-box.y1});
    }
  }
  function selectEntry(node){
    if(c4Map){inspect(node);return;}
    if(!cy.getElementById(node.id).length&&!$('file-detail').hidden){
      allFileDeclarations=true;
      render(false,node.id);
    }else if(!view.canvas)focusNavigatorNode(node.id);
    inspect(node);
  }
  function renderSpecReport(report){
    const panel=$('spec-report');
    panel.hidden=!report;
    if(!report)return;
    panel.dataset.tone=report.tone;
    $('spec-symbol').textContent=report.symbol;
    $('spec-verdict').textContent=report.title;
    $('spec-scope').textContent=[report.scope||'Specification model only',...report.open.map(label=>'Open: '+label)].join('  ·  ');
  }
  function renderVerificationSummary(summary){
    const panel=$('verification-summary');
    const toggle=$('model-info-toggle');
    toggle.hidden=!summary&&!external?.review?.publication;
    toggle.textContent=summary?summary.symbol+' '+summary.title:'Model';
    toggle.setAttribute('aria-label',summary?summary.title+' · Verification details':'Verification details');
    toggle.title='Verification details';
    toggle.dataset.tone=summary?.tone||'neutral';
    if(toggle.hidden&&$('model-info').matches(':popover-open'))$('model-info').hidePopover();
    panel.hidden=!summary;
    if(!summary)return;
    panel.dataset.tone=summary.tone;
    $('verdict-symbol').textContent=summary.symbol;
    $('verdict-title').textContent=summary.title;
    $('verdict-domain').textContent=summary.backend+' · Generated model';
    $('verdict-subject').textContent=summary.subject;
    const formula=$('verdict-formula');
    formula.hidden=!summary.formula;
    formula.textContent=summary.formula;
    $('verdict-translation').textContent=summary.translation;
    const scope=$('verdict-scope');
    if(panel.dataset.session!==view.queryID)scope.open=false;
    panel.dataset.session=view.queryID;
    scope.hidden=!summary.scope;
    scope.querySelector('p').textContent=summary.scope;
  }
  function render(keep=false,reframeID){
    const entering=!!pendingDestination;
    finishDestination();
    closePicker();
    const contextView=!!view.extensions?.['c4.context'] || (!saved && !view.canvas && query.method==='graph.overview' && query.level==='context');
    if(!view.canvas&&$('trace-steps'))$('trace-steps').hidden=true;
    const container=view.extensions?.['c4.container'];
    const isMap=!!(view.extensions?.['c4.context']||container);
    const mapHost=$('c4-surface');
    const openingSystem=container&&c4Map&&contextOverview?.snapshotID===view.snapshotID&&
      !c4Map.subject&&contextOverview.nodes.some(n=>n.id===container.subject);
    const previousCamera=(keep||openingSystem)&&c4Map?{scale:c4Map.scale,cx:c4Map.cx,cy:c4Map.cy}:null;
    c4Map?.dispose();c4Map=undefined;
    mapHost.hidden=!isMap;
    setListView(entering?!!navigation?.list:!$('node-list').hidden);
    $('graph').hidden=isMap;
    $('container-level').hidden=!container;
    const fileOutline=!!view.extensions?.['file.outline'];
    const shared=!!canvas?.active;
    const term=shared?'':$('local-filter').value.trim().toLowerCase();
    const direction=shared?undefined:{right:'RIGHT',down:'DOWN'}[$('local-layout').value];
    let layoutRequest={canvas:view.canvas,direction,nodes:view.nodes.map(n=>({...n,...ArchitectureLayout.size(n)})),edges:view.edges};
    const fullModel=ArchitectureLayout.plan(layoutRequest);
    const links=fileOutline?view.edges.filter(edge=>edge.kind!=='contains'):[];
    const canFocusFiles=fileOutline&&links.length>0&&view.nodes.filter(node=>node.kind==='file').length>1;
    const compact=canFocusFiles&&!allFileDeclarations&&!term;
    if(compact){
      const ids=new Set();
      for(const edge of links)for(let id of [edge.source,edge.target]){
        while(id&&!ids.has(id)){ids.add(id);id=fullModel.parents.get(id);}
      }
      layoutRequest={...layoutRequest,nodes:layoutRequest.nodes.filter(n=>ids.has(n.id)),edges:view.edges.filter(e=>ids.has(e.source)&&ids.has(e.target))};
    }
    if(term){
      const ids=new Set();
      for(const node of view.nodes){
        if(![node.name,symbolKind(node)[0],node.anchor?.path].some(value=>value?.toLowerCase().includes(term)))continue;
        for(let id=node.id;id&&!ids.has(id);id=fullModel.parents.get(id))ids.add(id);
      }
      layoutRequest={...layoutRequest,nodes:layoutRequest.nodes.filter(n=>ids.has(n.id)),edges:view.edges.filter(e=>ids.has(e.source)&&ids.has(e.target))};
    }
    const listedNodes=term?layoutRequest.nodes:view.nodes,listedEdges=term?layoutRequest.edges:view.edges;
    const model=compact||term?ArchitectureLayout.plan(layoutRequest):fullModel;
    model.containmentCount=layoutRequest.edges.filter(e=>e.kind==='contains').length;
    model.edges=layoutRequest.edges;visibleLayout=model;
    const detail=$('file-detail');
    detail.hidden=!canFocusFiles;
    detail.textContent=compact?'Show all declarations':'Show linked declarations';
    detail.onclick=()=>{allFileDeclarations=!allFileDeclarations;clearSelection(false);render(false,true);};
    edgeHoverNode=undefined;cy?.edges().removeClass('hovered');$('graph').title='';renderEdgeLegend();
    renderSpecReport(view.canvas?.specReport);
    renderVerificationSummary(view.canvas?.verification);
    $('canvas-tools').hidden=false;
    $('canvas-filter').hidden=$('session-layout').hidden=$('session-options').hidden=!shared;
    $('local-filter').hidden=$('local-layout-control').hidden=shared;
    const sourceOptions=!shared&&!repositoryMode&&!contextView&&!isMap&&!saved;
    if(isMap)$('local-layout-control').hidden=true;
    $('source-filters').hidden=!sourceOptions;
    $('canvas-options-toggle').hidden=!sourceOptions&&!shared;
    if($('canvas-options-toggle').hidden&&$('canvas-options').matches(':popover-open'))$('canvas-options').hidePopover();
    $('level').hidden=!!view.canvas;$('diff').hidden=!!view.canvas;
    $('open-specification').hidden=saved||repositoryMode||!!view.canvas;
    $('list-toggle').hidden=false;$('export').hidden=false;
    $('follow-map').hidden=saved||!isMap||!query.snapshotID;
    $('snapshot-short').textContent=view.snapshotID.slice(0,8);$('counts').textContent=fileOutline?`${layoutRequest.nodes.length} entities on canvas · ${links.length} ${links.length===1?'link':'links'}`:`${view.nodes.length} entities · ${view.edges.length} relations`;
    $('workspace').textContent=container?.workspace||view.extensions?.['c4.context']?.workspace||view.nodes.find(n=>n.kind==='workspace')?.name||$('workspace').textContent;
    if(term)$('counts').textContent=listedNodes.length+' entities · '+listedEdges.length+' relations';
    renderBreadcrumbs();
    $('mode-label').textContent=isMap?'Map':contextView?'System Context':view.canvas?view.canvas.kind+' · '+view.canvas.format:model.cfg?'Control flow ↓':fileOutline?(compact?'Linked declarations':links.length?'File contents':'File contents · no links in this view'):view.nodes.some(n=>n.kind==='file'&&model.groups.has(n.id))?'File contents':model.groups.size?'Recorded scopes · dependencies ↓':'Relations ↓';
    if(view.extensions?.['implementation.scope'])$('mode-label').textContent=view.extensions['implementation.scope'];
    $('view-status').textContent=`${view.freshness} / ${view.completeness}`;
    $('footer-status').textContent=saved?'Saved snapshot · '+view.snapshotID+' · not live':`Snapshot ${view.snapshotID.slice(0,8)} · ${view.freshness} · ${view.coverage.length} coverage scopes`;
    $('more').hidden=!view.nextCursor;$('scope-count').textContent=String(listedNodes.length);$('empty').hidden=!!listedNodes.length;
    const empty=$('empty');
    empty.replaceChildren();
    if(term&&!listedNodes.length)empty.textContent='No matching entities.';
    else{empty.textContent='No recorded entities in this view.';}
    const nav=$('navigator'),list=$('node-list');nav.replaceChildren();list.replaceChildren();
    const nodes=new Map(view.nodes.map(n=>[n.id,n])),parents=model.parents,owners=fullModel.owners;
    listedNodes.forEach(node=>{const [kind,icon]=symbolKind(node),language=languageName(node),context=nodeContext(node,owners,nodes);const entry=button('',()=>selectEntry(node));entry.dataset.entityId=node.id;entry.title=[kind,language,node.name,context.detail,context.source].filter(Boolean).join(' · ');entry.append(roleMark(node),text('span',nodeTitle(node),'node-name'),text('span',kind,'node-kind'));entry.addEventListener('dblclick',()=>expand(node));nav.append(entry);
      const row=button('',()=>selectEntry(node));row.dataset.entityId=node.id;row.className='entity-row';const content=text('span','','entity-content');content.append(text('span',nodeTitle(node),'entity-name'),text('span',[context.detail,context.source||'No source anchor'].filter(Boolean).join(' · '),'entity-context'));row.append(roleMark(node),content,text('span',[kind,language,context.synthetic?'Synthetic':''].filter(Boolean).join(' · '),'entity-type'));row.addEventListener('dblclick',()=>expand(node));list.append(row);});
    if(!term&&!view.canvas&&query.method==='graph.search'&&query.text){
      const filter={text:query.text};
      external?.modelSlot(nav,filter,count=>{$('scope-count').textContent=String(view.nodes.length+count);});
      external?.modelSlot(list,filter);
      if(!view.nodes.length){
        const message=text('span','No matching source entities.');
        empty.replaceChildren(message);
        external?.modelSlot(empty,filter,count=>{message.hidden=count>0;});
      }
    }
    if(listedEdges.length)list.append(text('h2','Relations','list-heading'));
    listedEdges.forEach(edge=>{const row=button('',()=>view.canvas?inspectCanvasEdge(edge.id):inspectSourceEdge(edge));row.className='relation-row';row.append(relationSwatch(relationStyle(edge)),text('span',`${nodes.get(edge.source)?.name||edge.source} → ${nodes.get(edge.target)?.name||edge.target}`,'relation-endpoints'),text('span',relationName(edge),'relation-kind'));list.append(row);});
    if(isMap && view.nodes.length){
      ++layoutGeneration;lastLayoutKey=undefined;layoutReadyQuery=query;
      syncHeaderMenus([]);refreshWorkspaceModels();
      if(!container)contextOverview={snapshotID:view.snapshotID,nodes:view.nodes};
      c4Map=new C4Map(mapHost,view,{
        overview:container&&contextOverview?.snapshotID===view.snapshotID?contextOverview.nodes:[],
        node:inspect,edge:inspectSourceEdge,expand,clear:clearSelection,
        menu:!saved&&external?(anchor,n,point)=>openPicker(anchor,n,anchor,point):null,
        zoom:scale=>{$('zoom-value').textContent=Math.round(scale*100)+'%';}
      });
      if(term){
        const matches=new Set(listedNodes.map(n=>n.id));
        for(const target of c4Map.svg.querySelectorAll('[data-id],[data-owner]')){
          target.classList.toggle('c4-muted',!matches.has(target.dataset.id||target.dataset.owner));
        }
      }
      if(container&&!view.nodes.some(n=>n.attributes?.['context.owner']===container.subject)){
        $('mode-label').textContent=view.truncated?'Map · Partial page':'Map · No declared containers';
      }
      const camera=previousCamera||navigation?.c4Camera;
      if(camera&&[camera.cx,camera.cy,camera.scale].every(Number.isFinite)&&camera.scale>0){
        Object.assign(c4Map,camera);c4Map.paint();
      }
      c4Map.select(selectedFact||selected?.id);
      if(canvas?.sessions&&!saved)void refreshMapReports(canvas.sessions);
      return;
    }
    const elements=[...layoutRequest.nodes.map(n=>({group:'nodes',data:cardData(n,owners,nodes,model.groups)})),...layoutRequest.edges.filter(e=>!model.hidden.has(e.id)).map(e=>({group:'edges',data:{id:e.id,source:e.source,target:e.target,relation:relationStyle(e).key,...(e.attributes?.['context.operation']?{canvasLabel:e.attributes['context.operation']}:{}),...(e.canvas?{canvasLabel:e.canvas.label||'',canvasRole:e.canvas.role||'',canvasDirected:e.canvas.directed===false?0:1,canvasLoop:e.source===e.target}:{}),description:`${nodes.get(e.source)?.name||e.source} — ${relationName(e)} → ${nodes.get(e.target)?.name||e.target}`}}))];
    if(!cy){cy=cytoscape({container:$('graph'),userZoomingEnabled:false,elements:[],minZoom:.12,maxZoom:3,style:graphStyle()});cy.on('tap','node',e=>{if(tappedAccessory(e))return;const node=view.nodes.find(n=>n.id===e.target.id());if(node)inspect(node);});cy.on('dbltap','node',e=>{const node=view.nodes.find(n=>n.id===e.target.id());if(node)expand(node);});cy.on('zoom',()=>{$('zoom-value').textContent=Math.round(cy.zoom()*100)+'%';});cy.on('pan zoom',()=>canvas?.camera());
      cy.on('viewport resize',()=>{syncHeaderViewport();positionPicker();});cy.on('position bounds',queueHeaders);
      cy.on('select unselect','node',refreshEdgeFocus);cy.on('pan zoom',clearEdgePreview);
      cy.on('tap',event=>{if(event.target===cy)clearSelection();});
      cy.on('drag','node',event=>{event.target.union(event.target.descendants()).connectedEdges().removeClass('routed direct');preserveFrameHeaders(event.target.ancestors());});
      cy.on('free','node',()=>{if(canvas?.active)canvas.geometry();});
      cy.on('tap','edge',event=>{if(view.canvas)inspectCanvasEdge(event.target.id());else {const edge=view.edges.find(item=>item.id===event.target.id());if(edge)inspectSourceEdge(edge);}});
      cy.on('mouseover','node',event=>{if(!event.target.isParent()){edgeHoverNode=event.target.id();refreshEdgeFocus();}const node=view.nodes.find(n=>n.id===event.target.id());if(node)$('graph').title=[node.name,symbolKind(node)[0],languageName(node),typeof node.attributes?.['syntax.signature']==='string'?node.attributes['syntax.signature']:''].filter(Boolean).join(' · ');});
      cy.on('mouseout','node',event=>{if(edgeHoverNode&&edgeHoverNode!==event.target.id())return;edgeHoverNode=undefined;refreshEdgeFocus();$('graph').title='';});
      cy.on('mouseover','edge',event=>{event.target.addClass('hovered');$('graph').title=event.target.data('description');});
      cy.on('mouseout','edge',event=>{event.target.removeClass('hovered');$('graph').title='';});
      // Trackpad scrolling pans the canvas; browser pinch gestures arrive as control-wheel events.
      const canvasGesture=(name,listener)=>{
        for(const surface of [$('graph'),$('node-header-menus')])surface?.addEventListener(name,listener,{passive:false,capture:true});
      };
      canvasGesture('wheel',event=>{
        event.preventDefault();event.stopImmediatePropagation();
        const bounds=$('graph').getBoundingClientRect();
        const computed=getComputedStyle($('graph'));
        const line=parseFloat(computed.lineHeight)||parseFloat(computed.fontSize)*1.2;
        const unit=event.deltaMode===1?line:(event.deltaMode===2?bounds.height:1);
        const dx=event.deltaX*unit,dy=event.deltaY*unit;
        if(event.ctrlKey||event.metaKey){
          const level=Math.max(cy.minZoom(),Math.min(cy.maxZoom(),cy.zoom()*Math.exp(-dy*.01)));
          cy.zoom({level,renderedPosition:{x:event.clientX-bounds.left,y:event.clientY-bounds.top}});
        }else{
          cy.panBy({x:-(event.shiftKey&&dx===0?dy:dx),y:event.shiftKey&&dx===0?0:-dy});
        }
      });
      let gestureBaseZoom;
      canvasGesture('gesturestart',event=>{event.preventDefault();event.stopImmediatePropagation();gestureBaseZoom=cy.zoom();});
      canvasGesture('gesturechange',event=>{
        event.preventDefault();event.stopImmediatePropagation();
        if(gestureBaseZoom===undefined||!Number.isFinite(event.scale)||event.scale<=0)return;
        const bounds=$('graph').getBoundingClientRect();
        const x=Number.isFinite(event.clientX)?event.clientX-bounds.left:bounds.width/2;
        const y=Number.isFinite(event.clientY)?event.clientY-bounds.top:bounds.height/2;
        cy.zoom({level:Math.max(cy.minZoom(),Math.min(cy.maxZoom(),gestureBaseZoom*event.scale)),renderedPosition:{x,y}});
      });
      canvasGesture('gestureend',event=>{event.preventDefault();event.stopImmediatePropagation();gestureBaseZoom=undefined;});
    }
    cy.batch(()=>{
      const wanted=new Set(elements.map(e=>e.data.id));cy.elements().filter(e=>!wanted.has(e.id())).remove();
      for(const item of elements){const existing=cy.getElementById(item.data.id);if(existing.length)existing.data(item.data);else cy.add(item);}
      // Add every entity before assigning parents; IDs and input order carry no hierarchy assumptions.
      const reparent=cy.nodes().filter(node=>node.parent().id()!==parents.get(node.id()));
      reparent.move({parent:null});
      for(const node of reparent)if(parents.has(node.id()))node.move({parent:parents.get(node.id())});
    });
    refreshFrameCards();refreshEdgeFocus();syncHeaderMenus(layoutRequest.nodes);refreshWorkspaceModels();
    const generation=++layoutGeneration;
    if(keep&&lastLayoutKey===model.key){layoutReadyQuery=query;if(canvas?.active&&!canvas.session.state.geometry?.length)queueMicrotask(()=>canvas.geometry());return;}
    layoutReadyQuery=undefined;
    const message={...layoutRequest,generation,queryID:view.queryID,snapshotID:view.snapshotID};
    const receive=result=>{
      if(result.generation!==layoutGeneration||result.queryID!==view.queryID||result.snapshotID!==view.snapshotID)return;
      if(result.error){problem(Error(result.error));return;}
      cy.batch(()=>{
        cy.edges().removeClass('routed direct');
        for(const n of result.nodes){const element=cy.getElementById(n.id);if(element.length&&!element.isParent()){const fragment=element.data('kind')==='canvasFragment';if(fragment)element.data({width:n.width,height:n.height});element.position({x:n.x+(fragment?n.width:element.width())/2,y:n.y+(fragment?n.height:element.height())/2});}}
      });
      try{applyFrameGeometry(result.nodes);}catch(error){problem(error);return;}
      applyRoutes(result.routes);
      lastLayoutKey=model.key;layoutReadyQuery=query;
      if(view.canvas){
        if(canvas)canvas.applying=true;
        const state=canvas?.session?.state;
        if(state?.camera){cy.zoom(state.camera.zoom);cy.pan(state.camera.pan);}else if(!keep)fitFormalGraph();
        if(canvas&&canvas.focusKey!==canvas.session.viewSessionID+':'+state.focusNonce){canvas.focusKey=canvas.session.viewSessionID+':'+state.focusNonce;let targets=cy.collection();for(const id of state.focus||[])targets=targets.union(cy.getElementById(id));if(targets.length)cy.fit(targets,70);}
        if(canvas)canvas.applying=false;
        queueMicrotask(()=>{canvas?.geometry();canvas?.camera();});
      }else if(!keep){const camera=!reframeID&&navigation?.camera;if(camera&&Number.isFinite(camera.zoom)&&Number.isFinite(camera.pan?.x)&&Number.isFinite(camera.pan?.y)){cy.zoom(Math.max(cy.minZoom(),Math.min(cy.maxZoom(),camera.zoom)));cy.pan({...camera.pan});}else openCanvas();if(typeof reframeID==='string')focusNavigatorNode(reframeID);}
    };
    if(worker&&!saved){worker.onmessage=event=>receive(event.data);worker.postMessage(message);}
    else ArchitectureLayout.layout(message,new ELK()).then(receive).catch(problem);
  }
  function codeBlock(source,language,truncated=false){
    const block=text('pre',source,'code-preview');
    block.dataset.language=['swift','rust'].includes(language)?language:'plaintext';
    if(block.dataset.language!=='plaintext'){
      try{
        if(source.length>16384)throw Error('Highlighting limit reached; showing literal source.');
        if(typeof ArchitectureSyntax==='undefined'||!ArchitectureSyntax.getLanguage(language))throw Error('Bundled grammar is unavailable.');
        // The pinned grammar escapes source HTML and emits only token spans.
        block.innerHTML=ArchitectureSyntax.highlight(source,{language,ignoreIllegals:true}).value;
      }catch(error){block.append(text('span','\n'+(source.length>16384?error.message:'Highlighting unavailable: '+error.message),'code-notice'));}
    }
    if(truncated)block.append(text('span','\n… [range truncated]','code-notice'));
    return block;
  }
  async function refreshMapReports(sessions){
    const map=c4Map,scope=view;
    if(!map||saved||!canvas||map.readingReports)return;
    const key=JSON.stringify(sessions.filter(s=>s.format==='json').map(s=>[s.viewSessionID,s.revision]));
    if(map.reportKey===key)return;
    map.readingReports=true;
    const active=()=>map===c4Map&&scope===view;
    try{
      const entries=await canvas.mapReports({workspaceID:scope.workspaceID,snapshotID:scope.snapshotID},active,sessions);
      if(!active())return;
      map.reportKey=key;
      const same=map.reports&&map.reports.length===entries.length&&entries.every((e,i)=>e.id===map.reports[i].id&&e.digest===map.reports[i].digest);
      if(same&&!map.reportError)return;
      map.reportError=null;map.reports=entries;
    }catch(error){
      if(!active()||map.reportError===error.message)return;
      map.reportError=error.message;map.reportKey=null;map.reports=undefined;
    }finally{map.readingReports=false;}
    if(selected&&$('map-verification-results'))showMapReports(selected);
  }
  function showMapReports(node){
    const slot=$('map-verification-results');if(!slot)return;
    const map=c4Map;
    const entries=map?.reports?.filter(e=>e.binding.entityID===node.id);
    slot.replaceChildren();
    const addNote=message=>slot.append(text('p',message,'map-report-note'));
    if(map?.reportError){addNote('Reports unavailable · '+map.reportError);return;}
    if(!entries){addNote('Looking for reports…');return;}
    if(!entries.length){addNote('No linked reports for this snapshot.');return;}
    for(const entry of entries){
      const row=button('',()=>openMapVerification(node,entry),'map-report-row');
      const duplicate=entries.some(e=>e.id!==entry.id&&e.title===entry.title);
      row.append(text('strong',duplicate?entry.title+' · '+entry.digest.slice(0,8):entry.title));
      const {title,tone,open}=entry.summary;
      const outcome=text('span',title,'map-report-outcome');outcome.dataset.tone=tone;
      row.append(outcome);
      if(open.length)row.append(text('span',open.length+' open question'+(open.length===1?'':'s'),'map-report-note'));
      slot.append(row);
    }
  }
  async function openMapVerification(node,entry){
    const map=c4Map,scope=view;
    if(!map||!scope.nodes.some(item=>item.id===node.id))return;
    const active=()=>map===c4Map&&scope===view;
    const entries=map.reports?.filter(e=>e.binding.entityID===node.id)||[];
    if(!entry&&entries.length!==1){
      if(!entries.length)return;
      const picker=$('canvas-picker');closePicker();picker.replaceChildren();picker.setAttribute('aria-label','Verification reports for '+node.name);
      for(const item of entries){const duplicate=entries.some(other=>other.id!==item.id&&other.title===item.title);picker.append(button(item.title+(duplicate?' · '+item.digest.slice(0,8):'')+' · '+item.summary.title,()=>{closePicker();openMapVerification(node,item);}));}
      showPicker(picker,map.targets.get(node.id));return;
    }
    selected=node;map.select(node.id);
    try{
      await canvas.openMapReport(entry||entries[0],{workspaceID:view.workspaceID,snapshotID:view.snapshotID,entityID:node.id},active);
    }catch(error){if(active())problem(error);}
  }
  function inspectMapObject(box,node){
    const attrs=node.attributes||{}, nodes=new Map(view.nodes.map(n=>[n.id,n]));
    if(attrs['context.purpose'])box.append(text('p',attrs['context.purpose']));
    const fields=document.createElement('dl');
    const addField=(key,value)=>{if(value)fields.append(text('dt',key),text('dd',value));};
    const owner=nodes.get(attrs['context.owner']);
    const areas=attrs['context.areas']||owner?.attributes?.['context.areas']||[];
    addField('Domain',areas.map(area=>area.name).join(' › '));
    addField('System',owner?.name);
    addField('Runtime type',attrs['context.catalogType']);
    addField('Technology',attrs['context.technology']);
    if(Number.isInteger(attrs['context.containerCount']))addField('Declared containers',String(attrs['context.containerCount']));
    box.append(fields);
    if(canvas&&c4Map&&!saved){
      box.append(text('h3','Verification'));
      const slot=document.createElement('div');slot.id='map-verification-results';slot.setAttribute('aria-live','polite');
      box.append(slot);showMapReports(node);
    }
    if(node.kind==='softwareSystem'&&!saved){
      const actions=document.createElement('div');actions.className='action-row';
      if(view.extensions?.['c4.container']?.subject!==node.id&&attrs['context.containerCount']!==0)
        actions.append(button('Open containers',()=>expand(node)));
      actions.append(button('Focus system',()=>focusSystem(node)));box.append(actions);
    }
    if(attrs['context.owner']){
      if(!saved&&attrs['context.entryID'])box.append(button('Open components',()=>expand(node)));
      else if(!attrs['context.entryID'])box.append(text('p','No implementation link resolved in this snapshot.'));
    }
    const children=view.nodes.filter(child=>child.attributes?.['context.owner']===node.id);
    if(children.length){
      box.append(text('h3','Containers'));
      for(const child of children)box.append(button(child.name,()=>inspect(child),'map-peer'));
    }
    const relations=view.edges.filter(edge=>edge.source===node.id||edge.target===node.id);
    box.append(text('h3','Connections'));
    if(!relations.length)box.append(text('p','No connections in this view.'));
    for(const edge of relations){
      const outgoing=edge.source===node.id,peer=nodes.get(outgoing?edge.target:edge.source);
      const row=document.createElement('div');row.className='map-connection';
      row.append(text('span',outgoing?'To':'From'));
      if(peer)row.append(button(peer.name,()=>inspect(peer),'map-peer'));
      else row.append(text('span','Endpoint outside this view'));
      const operation=button([relationName(edge),edge.attributes?.['context.technology']].filter(Boolean).join(' · '),()=>inspectSourceEdge(edge),'map-operation');
      row.append(operation);box.append(row);
    }
    if(attrs['context.citedSources']?.length){
      box.append(text('h3','Implementation references'));
      for(const source of attrs['context.citedSources'])box.append(text('p',source.path+(source.line?':'+source.line:''),'reference-location'));
    }
    if(node.anchor){
      const declaration=attrs['context.declaration'];
      box.append(text('h3','Model declaration'));
      if(declaration)appendModelDeclaration(box,declaration);
      else box.append(text('p',node.anchor.path,'reference-location'));
    }
  }
  function appendModelDeclaration(box,declaration){
    box.append(text('p',declaration.path+':'+declaration.line,'reference-location'),codeBlock(declaration.text,'plaintext'));
  }
  async function inspect(node){
    if(repositoryMode){openRepositoryNode(node);return;}
    if(node.canvas||node.canvasOrigin){inspectCanvas(node.canvasOrigin?{...node,canvas:node.canvasOrigin}:node);return;}
    if(external?.review&&external.review.entity.id!==node.id)external.closeModel();
    const serial=++inspection;selectedFact=undefined;selected=node;c4Map?.select(node.id);if(cy){cy.elements().unselect();cy.nodes().removeClass('reference-endpoint');cy.getElementById(node.id).select();}
    for(const entry of document.querySelectorAll('[data-entity-id]')){const active=entry.dataset.entityId===node.id;entry.classList.toggle('active',active);entry.setAttribute('aria-pressed',String(active));}
    const box=$('inspector');box.replaceChildren(...inspectorBadges(node),text('h2',nodeTitle(node)));
    if(!saved&&node.kind==='workspace'){
      const snapshotID=view.snapshotID;
      const specification=text('section','','workspace-specification');
      const status=text('p','Loading specification…','subtle');status.setAttribute('role','status');
      specification.append(text('h3','Specification'),status);box.append(specification);
      external?.modelCommand(box,node,()=>{});
      external?.modelSlot(box,{entity:node.id,projectOnly:true});
      try{
        const result=await readWorkspaceSpecification(snapshotID);
        if(serial!==inspection||selected?.id!==node.id||snapshotID!==view.snapshotID)return;
        if(result.status==='missing'){status.textContent='No SPEC.md recorded in this workspace.';return;}
        const detail=document.createElement('details');detail.open=true;
        const content=text('pre',result.text);content.style.whiteSpace='pre-wrap';
        detail.append(text('summary',result.path),content);status.replaceWith(detail);
      }catch(error){if(serial===inspection&&selected?.id===node.id)status.textContent=error.message;}
      return;
    }
    if(!saved&&!c4Map&&external){
      const verification=text('section','','selection-verification');verification.append(text('h3','Verification'));
      external.modelCommand(verification,node,()=>{});
      const status=text('p','Loading published evidence…','subtle');status.setAttribute('role','status');verification.append(status);
      external.modelSlot(verification,{entity:node.id},count=>{status.textContent=count?'Published models and evidence':'No published evidence for this snapshot.';});box.append(verification);
    }else external?.modelSlot(box,{entity:node.id});
    if(view.extensions?.['c4.context']||view.extensions?.['c4.container']||node.kind==='softwareSystem'||node.attributes?.['context.owner']){
      inspectMapObject(box,node);
      if(node.anchor&&!saved&&!node.attributes?.['context.declaration']){
        try{
          const source=await rpc('source.read',{entityID:node.id,snapshotID:view.snapshotID});
          if(serial===inspection&&selected?.id===node.id)box.append(codeBlock(source.text,node.language,source.truncated));
        }catch(error){if(serial===inspection&&selected?.id===node.id)box.append(text('p',error.message));}
      }
      return;
    }
    const actions=document.createElement('div');actions.className='action-row';
    for(const [label,,action] of sourceCommands(node))actions.append(button(label==='Expand'&&view.extensions?.['implementation.scope']?'Open code':label,action));
    box.append(actions);
    const file=node.kind==='file';
    const members=file?new Set([node.id,...cy.getElementById(node.id).descendants().map(n=>n.id())]):null;
    const references=view.edges.filter(e=>e.kind==='candidateTypeReference'&&
      (file?members.has(e.source)!==members.has(e.target):e.source===node.id||e.target===node.id));
    if(references.length){
      const names=new Map(view.nodes.map(n=>[n.id,n.name]));
      const links=document.createElement('div');links.className='action-row';
      for(const edge of references){
        const outgoing=edge.source===node.id;
        const label=file?names.get(edge.source)+' → '+names.get(edge.target):outgoing?'→ '+names.get(edge.target):'← '+names.get(edge.source);
        links.append(button(label,()=>inspectTypeReference(edge)));
      }
      box.append(text('h3',file?'CROSS-FILE TYPE REFERENCES':'POSSIBLE TYPE REFERENCES'),links);
    }
    if(node.attributes?.['syntax.signature'])box.append(text('h3','DECLARATION'),codeBlock(node.attributes['syntax.signature'],node.language));
    box.append(text('h3','SOURCE & IDENTITY'));const details=document.createElement('dl');for(const[key,value]of [['Path',node.anchor?.path||'No source anchor'],['UTF-8 bytes',node.anchor?`${node.anchor.startByte}–${node.anchor.endByte}`:'Not available'],['Entity ID',node.id],['Input digest',node.anchor?.digest||node.entityRevision]]){details.append(text('dt',key),text('dd',value));}box.append(details);
    if(node.attributes?.['syntax.conditions'])box.append(text('p','Conditional activation is unknown: '+node.attributes['syntax.conditions'].join(' / ')));
    box.append(text('h3','RECORDED EVIDENCE'));
    const evidence=view.evidence.filter(e=>e.anchor?.path===node.anchor?.path);
    evidence.forEach(e=>{const section=text('div',`${e.basis} · ${e.freshness}\n${e.producer} / ${e.version}`,'evidence');box.append(section);});
    if(!evidence.length)box.append(text('p','No source evidence is bundled for this entity.'));
    view.coverage.filter(c=>c.scope===node.anchor?.path||c.scope===node.id).forEach(c=>box.append(text('p',`${c.completeness} · Excludes: ${c.exclusions.join(', ')}`)));
    box.append(text('h3','SOURCE PREVIEW'));
    if(saved){box.append(text('p','Source bodies are not bundled in this saved view.'));return;}
    try{const source=await rpc('source.read',{entityID:node.id,snapshotID:view.snapshotID});if(serial!==inspection||selected?.id!==node.id)return;box.append(codeBlock(source.text,node.language,source.truncated));}catch(error){if(serial===inspection&&selected?.id===node.id)box.append(text('p',error.message));}
  }
  function inspectSourceEdge(edge,restore=false){
    if(edge.kind==='candidateTypeReference')return inspectTypeReference(edge,restore);
    inspectContextEdge(edge.id);
  }
  async function inspectTypeReference(edge,restore=false){
    clearSelection(false);selectedFact=edge.id;
    const selectedEdge=cy.getElementById(edge.id).select();
    refreshEdgeFocus();
    const endpoints=selectedEdge.connectedNodes().addClass('reference-endpoint'),bounds=endpoints.renderedBoundingBox(),padding=24;
    if(!restore&&(bounds.x1<padding||bounds.y1<padding||bounds.x2>cy.width()-padding||bounds.y2>cy.height()-padding)){
      const zoom=cy.zoom();cy.fit(endpoints,padding);cy.zoom(Math.min(zoom,cy.zoom()));cy.center(endpoints);
    }
    const serial=inspection, snapshotID=view.snapshotID;
    const owner=view.nodes.find(n=>n.id===edge.source),target=view.nodes.find(n=>n.id===edge.target);
    const site=edge.attributes?.['reference.site'],box=$('inspector');
    box.replaceChildren(text('h2','Possible type reference'),text('p',owner.name+' → '+target.name));
    external?.modelSlot(box,{fact:edge.id});
    if(!site||!owner.anchor)return;
    box.append(text('p','The source spelling matches one type declaration in '+edge.attributes['reference.scope']+'.'),
      text('h3','SOURCE EXPRESSION'),text('p',owner.anchor.path+':'+site.line,'reference-location'));
    if(saved){box.append(text('p','Source text is unavailable in this saved view.'));return;}
    try{
      const source=await rpc('source.read',{entityID:owner.id,snapshotID,startByte:site.startByte,endByte:site.endByte});
      if(serial===inspection&&snapshotID===view.snapshotID)box.append(codeBlock(source.text,owner.language,source.truncated));
    }catch(error){if(serial===inspection&&snapshotID===view.snapshotID)box.append(text('p',error.message));}
  }
  function inspectContextEdge(id){
    const edge=view.edges.find(e=>e.id===id);
    if(!edge)return;
    clearSelection(false);selectedFact=id;c4Map?.select(id);cy?.getElementById(id).select();
    const box=$('inspector'),name=id=>view.nodes.find(n=>n.id===id)?.name||id;
    box.replaceChildren(text('h2',relationName(edge)),text('p',name(edge.source)+' → '+name(edge.target)));
    external?.modelSlot(box,{fact:id});
    if(!edge.attributes?.['context.operation'])return;
    const declarations=edge.attributes['context.declarations'];
    if(declarations?.length){
      box.append(text('h3','Model declarations'));
      for(const declaration of declarations)appendModelDeclaration(box,declaration);
      return;
    }
    box.append(text('h3','CATALOG RECORDS'));
    for(const record of view.evidence.filter(e=>edge.evidenceIDs.includes(e.id))){
      box.append(text('p',record.anchor?.path||record.id),text('code',record.inputDigest));
    }
  }
  function inspectCanvasEdge(id){
    const edge=view.edges.find(e=>e.id===id);if(!edge?.canvas)return;
    cy.elements().unselect();cy.getElementById(id).select();selected=undefined;
    if(repositoryMode){
      const name=id=>view.nodes.find(node=>node.id===id)?.name||id;
      $('inspector').replaceChildren(text('h2',edge.canvas.label||edge.canvas.role),text('p',name(edge.source)+' → '+name(edge.target)),text('h3','EVIDENCE'),text('p',edge.canvas.details?.evidence||edge.canvas.details?.declaredIn||''));
      return;
    }
    $('inspector').replaceChildren(text('h2',edge.canvas.label||edge.id),text('p',edge.canvas.role||'Relation'),text('p',edge.source+' → '+edge.target),text('pre',JSON.stringify(edge.canvas.details||{},null,2),'code-preview'));
    if(canvas&&!canvas.applying)canvas.selection([id]);
  }
  function inspectCanvas(node){
    for(const entry of document.querySelectorAll('[data-entity-id]')){const active=entry.dataset.entityId===node.id;entry.classList.toggle('active',active);entry.setAttribute('aria-pressed',String(active));}
    inspection++;selected=node;if(cy){cy.elements().unselect();cy.nodes().removeClass('reference-endpoint');cy.getElementById(node.id).select();}
    const box=$('inspector');box.replaceChildren(text('h2',node.name),...inspectorBadges(node));
    const report=canvas?.session.document.metadata?.verificationReport;
    const requirement=report?.requirements?.find(row=>row.nodeID===node.id);
    const grouped=report&&node.canvas.role==='requirement group'?report.requirements.filter(row=>canvas.session.document.nodes.some(item=>item.id===row.nodeID&&item.parentID===node.id)):null;
    if(requirement){
      box.append(text('p',node.canvas.details?.condition||''));
      for(const phase of ['specification','implementation','correspondence']){
        const assessment=requirement[phase];box.append(text('h3',phase.toUpperCase()),text('p',assessment.outcome==='notVerified'?'Not verified':assessment.outcome));
        if(assessment.detail)box.append(text('p',assessment.detail));
        for(const id of assessment.claims){const claim=report.evidence.find(item=>item.id===id);if(claim)box.append(text('p',claim.scope));}
      }
    }else if(grouped){
      for(const phase of ['specification','implementation','correspondence'])box.append(text('h3',phase.toUpperCase()),text('p',`${grouped.filter(row=>row[phase].outcome==='passed').length} of ${grouped.length} verified`));
      box.append(text('h3','REQUIREMENTS'),...grouped.map(row=>text('p',`${row.id} · ${row.title}`)));
    }else box.append(text('h3','DIAGRAM DETAILS'),text('pre',JSON.stringify(node.canvas.details||{},null,2),'code-preview'));
    const actions=document.createElement('div');actions.className='action-row';
    if(canvas?.session.document.nodes.some(n=>n.parentID===node.id)){const collapsed=canvas.session.state.collapsed.includes(node.id);actions.append(button(collapsed?'Expand':'Collapse',()=>canvas.command(collapsed?'canvas.expand':'canvas.collapse',{ids:[node.id]}).catch(problem)));}
    actions.append(button('Focus',()=>canvas.command('canvas.focus',{ids:[node.id]}).catch(problem)));box.append(actions);
    const source=node.canvas.source;if(source&&source!==null){box.append(text('h3','ORIGINAL SOURCE'),text('pre',JSON.stringify(source,null,2),'code-preview'));if(source.entityID&&source.snapshotID)box.append(button('Open source',()=>go({method:'graph.neighbors',focus:source.entityID,snapshotID:source.snapshotID,depth:0})));}
    box.append(text('h3','FILE & PROVENANCE'),text('p',canvas?.session.document.sourceName||''));
    if(report){if(node.canvas.details?.requirement)box.append(text('p',node.canvas.details.requirement));for(const receipt of report.receipts||[])box.append(text('p',receipt.path));}
    else box.append(text('pre',JSON.stringify(canvas?.session.document.metadata||{},null,2),'code-preview'));
    if(canvas&&!canvas.applying)canvas.selection([node.id]);
  }
  function focusSystem(node){go({method:'graph.overview',level:'context',focus:node.id,snapshotID:view.snapshotID});}
  function expand(node){if(repositoryMode)return;if(node.attributes?.['context.owner']){const entry=node.attributes['context.entryID'];if(entry&&!saved)go({method:'graph.overview',level:'component',focus:entry,snapshotID:view.snapshotID});else inspect(node);return;}if(node.kind==='softwareSystem'){if(!saved)go({method:'graph.overview',level:'container',focus:node.id,snapshotID:view.snapshotID});return;}if(node.canvas||node.canvasOrigin){const origin=node.canvasOrigin||node.canvas;if(!canvas.session.document.nodes.some(n=>n.parentID===node.id)){if(origin.source?.entityID&&origin.source?.snapshotID)go({method:'graph.neighbors',focus:origin.source.entityID,snapshotID:origin.source.snapshotID,depth:0});else inspect(node);return;}const collapsed=canvas.session.state.collapsed.includes(node.id);canvas.command(collapsed?'canvas.expand':'canvas.collapse',{ids:[node.id]}).catch(problem);return;}if(saved){problem(Error('This saved snapshot includes only the exported view. Lower hierarchy is not bundled.'));return;}openScope(node);}
  $('follow-map').onclick=()=>{
    const {snapshotID,cursor,...live}=query;
    go(live);
  };
  $('workspace-home').onclick=event=>{
    event.preventDefault();
    if(!saved)go({method:'graph.overview',level:'context',...(query.snapshotID?{snapshotID:query.snapshotID}:{})});
  };
  $('back').onclick=()=>{if(!saved&&navigation?.index>0)window.history.back();};
  $('open-specification').onclick=()=>{
    if($('open-specification').hidden||!view?.snapshotID)return;
    go({method:'workspace.specification',snapshotID:view.snapshotID});
    $('back').focus({preventScroll:true});
  };
  $('level').onchange=()=>{
    const level=$('level').value;
    const inContainer=view?.extensions?.['c4.container']&&selected?.attributes?.['context.owner'];
    const inSource=view?.extensions?.['implementation.scope'];
    if((inContainer||inSource)&&['component','function','file'].includes(level)){
      const entry=inContainer?selected.attributes['context.entryID']:query.focus;
      if(!entry){$('level').value=query.level;inspect(selected);return;}
      if(level==='file')go({method:'graph.children',level,focus:entry,depth:2,snapshotID:view.snapshotID});
      else go({method:'graph.overview',level,focus:entry,snapshotID:view.snapshotID});
      return;
    }
    go({method:'graph.overview',level,...(query.snapshotID?{snapshotID:query.snapshotID}:{})});
  };
  for(const id of ['relation','language','direction'])$(id).onchange=()=>go({...query,kinds:$('relation').value?[$('relation').value]:[],languages:$('language').value?[$('language').value]:[],direction:$('direction').value});
  $('search').oninput=()=>{clearTimeout(searchTimer);searchTimer=setTimeout(()=>{const value=$('search').value;if(saved){if(c4Map){$('local-filter').value=value;render(true);return;}const matches=view.nodes.filter(n=>n.name.toLowerCase().includes(value.toLowerCase()));cy.nodes().style('opacity',.18);matches.forEach(n=>cy.getElementById(n.id).style('opacity',1));return;}go(value?{method:'graph.search',text:value,limit:50}:{method:'graph.overview',level:$('level').value==='container'?'context':$('level').value},query.method==='graph.search'&&!!value);},180);};
  document.addEventListener('keydown',event=>{if(!repositoryMode&&event.key==='/'&&event.target.tagName!=='INPUT'){event.preventDefault();$('search').focus();}if(event.key==='Escape'){$('search').blur();clearSelection();}});
  $('list-toggle').onclick=()=>setListView($('node-list').hidden);
  let localFilterTimer;
  function redrawLocalCanvas(){
    if(!view||canvas?.active||navigation?.verification||repositoryMode&&!repositoryPage)return;
    render(false,true);
    if(repositoryPage)renderRepositoryChrome(repositoryPage,repositoryRoute());
  }
  $('local-filter').oninput=()=>{
    clearTimeout(localFilterTimer);
    localFilterTimer=setTimeout(redrawLocalCanvas,140);
  };
  $('local-layout').onchange=redrawLocalCanvas;
  $('fit').onclick=()=>{if(c4Map)c4Map.fit();else if(cy)fitCanvas(70);};$('zoom-in').onclick=()=>c4Map?c4Map.zoomBy(1.2):cy?.zoom(cy.zoom()*1.2);$('zoom-out').onclick=()=>c4Map?c4Map.zoomBy(1/1.2):cy?.zoom(cy.zoom()/1.2);
  $('more').onclick=()=>go({...query,snapshotID:view.snapshotID,cursor:view.nextCursor});
  $('diff').onclick=async()=>{terminal.setOpen(true);try{const status=await rpc('workspace.status');if(status.history.length<2)throw Error('Only one snapshot has been recorded.');const delta=await rpc('graph.diff',{from:status.history[1],to:status.history[0]});terminal.write('info',`Latest change: ${delta.upsertNodes.length} updated/added entities, ${delta.removeNodeIDs.length} removed, ${delta.upsertEdges.length} updated relations. ${delta.baseSnapshotID} → ${delta.targetSnapshotID}`);}catch(error){problem(error);}};
  const workspaceActions=$('workspace-actions');
  function closeWorkspaceActions(){
    if(workspaceActions.matches(':popover-open'))workspaceActions.hidePopover();
  }
  workspaceActions.addEventListener('click',event=>{
    if(event.target.closest('button'))closeWorkspaceActions();
  });
  workspaceActions.addEventListener('change',closeWorkspaceActions);
  $('export').onclick=async()=>{try{if(canvas?.active){await downloadCanvas('json');return;}const data=saved?JSON.stringify(view,null,2):(await rpc('graph.export',{query:{...query,snapshotID:view.snapshotID},format:'json'})).text;const url=URL.createObjectURL(new Blob([data],{type:'application/json'}));const link=document.createElement('a');link.href=url;link.download='architecture-view.json';link.click();URL.revokeObjectURL(url);}catch(error){problem(error);}};
  async function downloadCanvas(format){const result=await rpc('canvas.export',{viewSessionID:canvas.session.viewSessionID,format});const url=URL.createObjectURL(new Blob([result.text],{type:format==='svg'?'image/svg+xml':'application/json'}));const link=document.createElement('a');link.href=url;link.download=canvas.session.document.title.replace(/\.[^.]+$/,'')+'.'+format;link.click();URL.revokeObjectURL(url);}
  if($('canvas-export-svg'))$('canvas-export-svg').onclick=()=>downloadCanvas('svg').catch(problem);
  let reconnecting=false;
  function connect(){
    const socket=new WebSocket('ws://'+location.host+'/events');
    let lastProgress, ready=false, rejected=false;
    socket.onmessage=event=>{
      const value=JSON.parse(event.data);
      if(rejected)return;
      if(value.type==='liveUnavailable'){
        rejected=true;
        $('live').textContent='Live index unavailable';$('live').classList.add('offline');
        terminal.write('error',value.message);
        return;
      }
      if(!ready){
        ready=true;reconnecting=false;
        $('live').textContent='Live index';$('live').classList.remove('offline');
        terminal.write('info','Connected to the live index.');
      }
      if(value.extensionChanged)external?.refresh().catch(problem);
      streamEpoch=value.streamEpoch;
      if(value.type==='analysisStatusChanged'){
        const p=value.progress||{};
        const message=p.totalSources?`Indexing ${p.completedSources||0} / ${p.totalSources} source scopes · ${p.runningWorkers||0} active workers`:'Collecting saved source inputs…';
        $('footer-status').textContent=message;$('live').textContent='Indexing';
        const progress=p.totalSources?Math.floor((p.completedSources||0)*10/p.totalSources):'collecting';
        if(progress!==lastProgress)terminal.write('info',message);
        lastProgress=progress;
      }else if(value.type==='viewInvalidated'){
        $('live').textContent='Live index';lastProgress=undefined;
        terminal.write('info','Index snapshot '+value.snapshotID+' is available.');
        if(!canvas?.active&&(!view||value.snapshotID!==view.snapshotID)&&!query.snapshotID)load(true).catch(problem);
      }
    };
    socket.onclose=()=>{
      if(rejected)return;
      $('live').textContent='Disconnected · may be stale';$('live').classList.add('offline');
      if(!reconnecting)terminal.write('warn','Live index disconnected. Reconnecting…');
      reconnecting=true;
      setTimeout(connect,1500);
    };
  }
  function repositoryRoute(){
    const params=new URLSearchParams(location.hash.slice(1));
    const repo=params.get('repo');
    return repo?{repo,path:params.getAll('entry'),...(params.has('service')?{service:params.get('service')}:{})}:{};
  }
  function repositoryNavigate(route){
    const params=new URLSearchParams();
    if(route.repo){params.set('repo',route.repo);for(const entry of route.path||[])params.append('entry',entry);}
    if(route.service)params.set('service',route.service);
    const hash='#'+params.toString();if(location.hash===hash)return;
    history.pushState({repositoryDepth:(history.state?.repositoryDepth||0)+1},'',hash);loadRepository();
  }
  function repositoryLanguage(path){return path.endsWith('.swift')?'swift':path.endsWith('.rs')?'rust':'plaintext';}
  function openRepositoryNode(node){
    if(!repositoryPage)return;
    const route=repositoryRoute();
    if(typeof repositoryPage.text==='string'){
      const encoded=new TextEncoder().encode(repositoryPage.text);
      const body=new TextDecoder().decode(encoded.subarray(node.canvas.startByte,node.canvas.endByte));
      $('inspector').replaceChildren(text('h2',node.name),...inspectorBadges(node),text('p',repositoryPage.title),codeBlock(body,repositoryLanguage(repositoryPage.title)));
      cy?.nodes().unselect();cy?.getElementById(node.id).select();
      return;
    }
    if(!route.repo){repositoryNavigate({repo:node.id});return;}
    if(node.canvas.service){repositoryNavigate({repo:route.repo,service:node.canvas.service});return;}
    const box=$('inspector');
    box.replaceChildren(text('h2',node.name),...inspectorBadges(node),text('h3','EVIDENCE'),text('p',node.canvas.details?.evidence||''));
    cy?.nodes().unselect();cy?.getElementById(node.id).select();
    if(node.canvas.sourcePath)box.append(button('Open source',()=>repositoryNavigate({repo:route.repo,path:node.canvas.sourcePath})));
  }
  async function loadRepository(){
    const route=repositoryRoute(),token=beginDestination(route.service||route.path?.at(-1)||route.repo||'Repositories','Reading selected repository…'),serial=++request;
    repositoryPage=undefined;$('local-filter').value='';
    if(!route.repo)$('back').disabled=true;
    $('repository-source')?.remove();
    const listing=$('node-list');
    const inspector=$('inspector');
    try{
      await destinationPaint();if(serial!==request)return;
      const result=await rpc('repository.browse',route);
      if(serial!==request)return;
      const file=typeof result.text==='string',outline=file&&!!result.nodes?.length,architecture=result.architecture;
      // An old directory bookmark resolves to the repository architecture, with a canonical URL.
      if(architecture&&route.path?.length){
        route.path=[];const params=new URLSearchParams({repo:route.repo});
        if(route.service)params.set('service',route.service);
        history.replaceState(history.state,'','#'+params.toString());
      }
      const sessionID=JSON.stringify(route);
      query={method:'repository.browse',...route};
      const doc={title:result.title,nodes:result.nodes||[],edges:result.edges||[],kind:'relations',format:'workspace',sourceDigest:'worktree'};
      view=ArchitectureCanvasModel.view({viewSessionID:sessionID,document:doc,state:{}});
      hierarchy={nodes:[]};selected=undefined;
      render();
      repositoryPage=result;
      terminal.write('info','Opened '+result.title);
      if(result.outlineNotice)terminal.write('warn',result.outlineNotice);
      renderRepositoryChrome(result,route);
      inspector.replaceChildren(text('h2',result.title.split('/').pop()),text('p',file?'Source file':architecture||'Repository collection'),text('p',result.title));
      if(architecture)inspector.append(text('p',architecture==='Deployment architecture'?'Select a service to inspect its entry point. Edges show declared deployment relationships.':architecture==='Entry-point composition'?'Construction and member-call expressions in the entry module. Select an edge to see its source location.':'Select an element or relationship to inspect its evidence.'));
      if(outline){
        inspector.append(text('h3','SOURCE PREVIEW'),codeBlock(result.text,repositoryLanguage(result.title)));
      }else if(file){
        $('empty').hidden=true;
        const block=codeBlock(result.text,repositoryLanguage(result.title),result.truncated);
        block.id='repository-source';block.tabIndex=0;block.setAttribute('aria-label','Source preview');$('graph').parentElement.append(block);
      }else if(!view.nodes.length){$('empty').textContent=architecture?'Architecture unresolved':'No repositories in scope.';}
      if(!listing.hidden&&file&&!outline)setListView(false);
    }catch(error){
      if(serial!==request)return;
      layoutGeneration++;cy?.elements().remove();$('navigator').replaceChildren();listing.replaceChildren();inspector.replaceChildren();
      failDestination(token,error,()=>loadRepository());
      $('breadcrumb').replaceChildren(button('Repositories',()=>repositoryNavigate({})));$('back').disabled=false;$('back').onclick=()=>history.back();problem(error);
    }
  }
  function renderRepositoryChrome(result,route){
    const file=typeof result.text==='string',outline=file&&!!result.nodes?.length,architecture=result.architecture;
    $('canvas-tools').hidden=file&&!outline;
    $('snapshot-short').parentElement.hidden=true;
    $('live').textContent='On demand';
    $('workspace').textContent='Repositories';
    $('workspace-home').onclick=event=>{event.preventDefault();repositoryNavigate({});};
    $('back').disabled=!route.repo;
    $('back').onclick=()=>{if(history.state?.repositoryDepth>0)history.back();else repositoryNavigate(route.repo&&(route.service||route.path?.length)?{repo:route.repo}:{});};
    const crumbs=$('breadcrumb');crumbs.replaceChildren(button('Repositories',()=>repositoryNavigate({})));
    if(route.repo){
      const names=architecture?(route.service?[result.checkout,route.service]:[result.checkout]):[result.title.split('/')[0],result.title.split('/').at(-1)];

      names.forEach((name,i)=>crumbs.append(text('span','›','crumb-separator'),i===names.length-1?text('span',name,'crumb-current'):button(name,()=>repositoryNavigate({repo:route.repo}))));
    }
    $('mode-label').textContent=architecture||(outline?'File declarations':file?'':'Repository map');
    $('view-title').textContent=result.title;
    $('list-toggle').hidden=file&&!outline;
    $('more').hidden=true;
    if(!$('local-filter').value.trim())$('counts').textContent=outline?view.nodes.length+' declarations':file?'Source preview':architecture?view.nodes.length+' elements · '+view.edges.length+' relationships':view.nodes.length+' repositories · '+view.edges.length+' dependencies';
    $('footer-status').textContent='Working tree · Read on navigation';
  }
  function startRepository(){
    for(const id of ['workspace-actions-toggle','diff','level','source-filters','canvas-tools'])$(id).hidden=true;
    $('search').parentElement.hidden=true;
    worker=new Worker('/assets/layout-worker.js');
    worker.onerror=event=>problem(Error('Layout worker failed: '+event.message));
    window.addEventListener('hashchange',()=>loadRepository());
    return loadRepository();
  }
  async function start(){setupPaneResizing();if(saved){setupNavigation();view=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(window.ARCHITECTURE_SAVED),c=>c.charCodeAt(0))));logGraph(view,'Opened saved snapshot');$('live').textContent='Saved · not live';$('live').classList.add('offline');external?.refresh().catch(problem);render();return;}
    const token=new URLSearchParams(location.hash.slice(1)).get('token');if(token){historyReplace();const response=await fetch('/session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({token})});if(!response.ok)throw Error('The launch token expired or was already used. Restart explore to open a new session.');}
    if(repositoryMode){await startRepository();return;}
    await loadHostContext().catch(problem);
    setupNavigation();worker=new Worker('/assets/layout-worker.js');worker.onerror=event=>problem(Error('Layout worker failed: '+event.message));
    if(navigation.verification)restoreVerification(navigation.verification).catch(problem);
    else if(navigation.canvasSessionID||new URLSearchParams(location.hash.slice(1)).get('canvas'))await canvas.openSession(navigation.canvasSessionID||new URLSearchParams(location.hash.slice(1)).get('canvas'),false).catch(problem);
    else if(navigation.loadingCanvas)failDestination(destinationSerial,Error('This pending diagram has no retained input. Return to the source and reopen it.'));
    else await load().catch(problem);
    connect();await canvas?.start();
    }
  function historyReplace(){window.history.replaceState(null,'',location.pathname);}
  start().catch(problem);
})();
