/* One revisioned imported view; drawing remains in Explorer's existing Canvas. */
'use strict';
window.ArchitectureCanvasUI=class {
  constructor(context){
    this.context=context;this.active=false;this.serial=0;this.queue=Promise.resolve();this.stopped=false;this.applying=false;this.contributionSessions=new Map();this.mapReportIndex=new Map();
    this.selector=document.getElementById('canvas-session');this.input=document.getElementById('canvas-files');this.openButton=document.getElementById('canvas-open');this.closeButton=document.getElementById('canvas-close');
    if(!this.selector)return;
    this.openButton.disabled=context.saved;this.selector.disabled=context.saved;this.closeButton.hidden=true;
    this.openButton.onclick=()=>this.input.click();this.input.onchange=()=>{const files=[...this.input.files];this.input.value='';this.files(files).catch(context.problem);};
    this.selector.onchange=()=>{if(this.selector.value)this.openSession(this.selector.value,true).catch(context.problem);else{this.leaveLocal();context.leave();}};
    this.closeButton.onclick=()=>{const session=this.session;this.leaveLocal();context.leave();this.mutate('canvas.close',{viewSessionID:session.viewSessionID,expectedRevision:session.revision}).then(()=>this.list()).catch(context.problem);};
    const graph=document.getElementById('graph');graph.addEventListener('dragover',event=>{event.preventDefault();});graph.addEventListener('drop',event=>{event.preventDefault();if(!context.saved)this.files([...event.dataTransfer.files]).catch(context.problem);});
    this.kind=document.getElementById('canvas-kind');this.kind.onchange=()=>this.command('canvas.setLayout',{kind:this.kind.value,layout:'auto'}).catch(context.problem);
    this.filter=document.getElementById('canvas-filter');this.layout=document.getElementById('canvas-layout');
    this.filter.oninput=()=>{
      clearTimeout(this.filterTimer);
      const session=this.session?.viewSessionID,text=this.filter.value;
      this.filterTimer=setTimeout(()=>{
        if(this.active&&session===this.session.viewSessionID)this.command('canvas.setFilter',{filter:{text}}).catch(context.problem);
      },180);
    };
    this.layout.onchange=()=>this.command('canvas.setLayout',{layout:this.layout.value}).catch(context.problem);
    window.addEventListener('pagehide',()=>{this.stopped=true;clearTimeout(this.pollTimer);clearTimeout(this.cameraTimer);clearTimeout(this.filterTimer);});
  }
  async start(){if(this.context.saved||!this.selector)return;const id=window.history.state?.canvasSessionID||new URLSearchParams(location.hash.slice(1)).get('canvas');if(id&&this.session?.viewSessionID!==id)await this.openSession(id,false);await this.list();this.poll();}
  begin(target,push,retry){
    const serial=++this.serial,transition=this.context.enter?.(target,push,retry);
    this.active=false;clearTimeout(this.cameraTimer);clearTimeout(this.filterTimer);
    if(this.closeButton)this.closeButton.hidden=true;
    return {serial,transition,paint:transition?.paint||Promise.resolve(),current:()=>serial===this.serial&&(!transition||transition.current())};
  }
  failed(load,error,retry){if(!load.current())return;this.context.error?.(load.transition,error,retry);throw error;}
  async mutate(method,params){
    const authority=await this.context.rpc('host.context');
    const response=await fetch('/canvas',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json',Authorization:'Bearer '+authority.csrf},body:JSON.stringify({method,params})});
    const value=await response.json();if(!response.ok||value.error){const error=Error((value.error?.code||'CANVAS_FAILED')+': '+(value.error?.message||response.status));error.code=value.error?.code;throw error;}return value;
  }
  async files(files){
    if(!files.length)return;const retry=()=>this.files(files).catch(this.context.problem),load=this.begin({title:files[0].name},true,retry);
    try{
      await load.paint;if(!load.current())return;
      if(files.length>32)throw Error('Open at most 32 diagram files at once.');const failures=[];let last;
      for(const file of files){if(!load.current())return;try{if(file.size>1024*1024)throw Error('File exceeds 1 MiB.');const bytes=await file.arrayBuffer();if(!load.current())return;const text=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(bytes);last=await this.mutate('canvas.open',{name:file.name,text});}catch(error){failures.push(file.name+': '+error.message);}}
      if(!load.current())return;if(last)this.present(last,true);this.list().catch(this.context.problem);if(failures.length){const error=Error(failures.join('\n'));if(last)this.context.problem(error);else throw error;}
    }catch(error){this.failed(load,error,retry);}
  }
  reportEntry(session){
    const report=session.document.metadata?.verificationReport||session.document.metadata?.specVerification,b=report?.mapBinding;
    if(!(Array.isArray(report?.requirements)||Array.isArray(report?.checks))||!b||![b.workspaceID,b.snapshotID,b.entityID].every(id=>typeof id==='string'&&id.length))return null;
    return {id:session.viewSessionID,title:session.document.title,digest:session.document.sourceDigest,binding:b,summary:window.ArchitectureCanvasModel.specificationReport(session.document).summary};
  }
  matchesMap(entry,target){
    return entry&&entry.binding.workspaceID===target.workspaceID&&entry.binding.snapshotID===target.snapshotID&&entry.binding.entityID===target.entityID;
  }
  async mapReports(target,active,sessions){
    if(!sessions)sessions=(await this.context.rpc('canvas.list')).sessions;
    const live=new Set(sessions.map(item=>item.viewSessionID));
    for(const id of this.mapReportIndex.keys())if(!live.has(id))this.mapReportIndex.delete(id);
    const matches=[],digests=new Set();
    for(const item of sessions){
      if(!active())break;
      if(item.format&&item.format!=='json')continue;
      const id=item.viewSessionID;
      let cached=this.mapReportIndex.get(id);
      if(cached?.revision!==item.revision){
        const session=await this.context.rpc('canvas.get',{viewSessionID:id});
        cached={revision:session.revision,entry:this.reportEntry(session)};
        this.mapReportIndex.set(id,cached);
      }
      const entry=cached.entry;
      if(entry&&entry.binding.workspaceID===target.workspaceID&&entry.binding.snapshotID===target.snapshotID&&
         (!target.entityID||this.matchesMap(entry,target))&&!digests.has(entry.digest)){
        digests.add(cached.entry.digest);matches.push(cached.entry);
      }
    }
    return matches.sort((a,b)=>a.title.localeCompare(b.title)||a.digest.localeCompare(b.digest));
  }
  async openMapReport(entry,target,active){
    if(!active())return;
    const retry=()=>this.openMapReport(entry,target,()=>true).catch(this.context.problem),load=this.begin({id:entry.id,title:entry.title,detail:'Loading verification report…'},true,retry);
    try{
      await load.paint;if(!load.current())return;
      const session=await this.context.rpc('canvas.get',{viewSessionID:entry.id});
      if(!load.current())return;
      const current=this.reportEntry(session);
      if(!this.matchesMap(current,target)||current.digest!==entry.digest)throw Error('The linked report changed. Return to the source and open its current report.');
      this.present(session,true);
    }catch(error){this.failed(load,error,retry);}
  }
  async contribution(data,publication,id,active=()=>true,resolve){
    if(!active())return;
    const retry=()=>this.contribution(data,publication,id,()=>true,resolve).catch(this.context.problem),load=this.begin({title:data.title||'Verification model'},true,retry);
    active=load.current;
    try{
    await load.paint;if(!active())return;
    if(resolve)data=await resolve();if(!active())return;
    const key=JSON.stringify([publication.publicationID,id]);
    const retained=this.contributionSessions.get(key);
    const model=window.ArchitectureCanvasModel.formalModel(data);
    const document={nodes:data.nodes,edges:data.edges,lanes:data.lanes,title:model?.title||data.title,kind:model?.kind||(data.kind&&window.ArchitectureCanvasModel.kinds.includes(data.kind)?data.kind:'relations'),metadata:{...(data.metadata?.verificationReport?{verificationReport:data.metadata.verificationReport}:{}),...(data.metadata?.formalKind==='verificationCondition'?{rankdir:'LR'}:{}),providerMetadata:data.metadata,providerID:publication.providerID,runID:publication.runID,publicationID:publication.publicationID,binding:publication.binding,applicability:publication.applicability,contributionID:id}};
    const source=JSON.stringify(document),name=id+'.json';
    const candidates=new Set(retained?[retained]:[]);
    for(const session of this.sessions||[])if(session.title===document.title)candidates.add(session.viewSessionID);
    if(candidates.size){
      const hash=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(source));
      const digest=Array.from(new Uint8Array(hash),byte=>byte.toString(16).padStart(2,'0')).join('');
      for(const viewSessionID of candidates){
        if(!active())return;
        const existing=await this.context.rpc('canvas.get',{viewSessionID});
        if(existing.document.sourceDigest!==digest||existing.document.sourceName!==name)continue;
        this.contributionSessions.set(key,viewSessionID);
        if(active())this.present(existing,true);
        return;
      }
    }
    if(!active())return;
    let result=await this.mutate('canvas.open',{name,text:source});
    if(!active())return;
    const steps=window.ArchitectureCanvasModel.traceOrder(result.document);
    if(steps.length)result=await this.mutate('canvas.select',{viewSessionID:result.viewSessionID,expectedRevision:result.revision,ids:[steps[0]]});
    this.contributionSessions.set(key,result.viewSessionID);
    if(active())this.present(result,true);this.list().catch(this.context.problem);
    }catch(error){this.failed(load,error,retry);}
  }
  async list(){const result=await this.context.rpc('canvas.list');this.sessions=result.sessions;const live=new Set(result.sessions.map(s=>s.viewSessionID));for(const [key,id] of this.contributionSessions)if(!live.has(id))this.contributionSessions.delete(key);const selected=this.session?.viewSessionID||'';this.selector.replaceChildren();const source=document.createElement('option');source.value='';source.textContent='Source workspace';this.selector.append(source);for(const session of result.sessions||[]){const option=document.createElement('option');option.value=session.viewSessionID;option.textContent=session.title+' · '+session.kind;this.selector.append(option);}this.selector.value=this.active?selected:'';}
  async openSession(id,push=false){
    const retry=()=>this.openSession(id,push).catch(this.context.problem),load=this.begin({id,title:this.sessions?.find(s=>s.viewSessionID===id)?.title||'Diagram'},push,retry);
    try{await load.paint;if(!load.current())return;const result=await this.context.rpc('canvas.get',{viewSessionID:id});if(load.current())this.present(result,push);}catch(error){this.failed(load,error,retry);}
  }
  present(session,push=false){
    if(this.session?.viewSessionID===session.viewSessionID&&session.revision<this.session.revision)return;
    const key=value=>JSON.stringify([value.viewSessionID,value.document.sourceDigest,value.document.kind,value.state.filter,value.state.collapsed,value.state.layout]);
    const unchanged=this.active&&this.session&&key(this.session)===key(session);this.session=session;this.active=true;this.applying=true;
    this.selector.value=session.viewSessionID;this.closeButton.hidden=false;this.filter.value=session.state.filter?.text||'';this.kind.value=session.document.kind;this.layout.value=session.state.layout||'auto';
    try{if(unchanged&&this.context.update)this.context.update(session);else{this.inspectionKey=null;this.context.present(session,push);}}finally{this.applying=false;}
  }
  leaveLocal(){this.serial++;this.active=false;this.session=undefined;if(this.selector){this.selector.value='';this.closeButton.hidden=true;}clearTimeout(this.cameraTimer);}
  command(method,params={}){
    const id=this.session?.viewSessionID,serial=this.serial;if(!id)return Promise.reject(Error('No imported Canvas session is active.'));
    const superseded=()=>Object.assign(Error('The diagram navigation was superseded.'),{code:'VIEW_SUPERSEDED'});
    const execute=async()=>{if(serial!==this.serial)throw superseded();if(!this.active||this.session?.viewSessionID!==id)throw Error('Canvas session changed.');let result;try{result=await this.mutate(method,{...params,viewSessionID:id,expectedRevision:this.session.revision});}catch(error){if(serial!==this.serial)throw superseded();if(error.code==='REVISION_CONFLICT')await this.openSession(id);else if(this.active&&this.session?.viewSessionID===id)this.present(this.session);throw error;}if(serial!==this.serial)throw superseded();if(result.document)this.present(result);return result;};
    const result=this.queue.then(execute);this.queue=result.catch(()=>{});return result;
  }
  camera(){if(!this.active||this.applying||!this.context.ready())return;clearTimeout(this.cameraTimer);const id=this.session.viewSessionID;this.cameraTimer=setTimeout(()=>{if(!this.active||this.session.viewSessionID!==id)return;const graph=this.context.graph();if(graph)this.command('canvas.setCamera',{camera:{zoom:graph.zoom(),pan:graph.pan()}}).catch(this.context.problem);},140);}
  geometry(){if(!this.active||this.applying||!this.context.ready())return;const graph=this.context.graph();if(!graph)return;const geometry=graph.nodes().map(n=>{const box=n.boundingBox({includeLabels:false,includeOverlays:false});return {id:n.id(),x:box.x1,y:box.y1,width:box.w,height:box.h};});this.command('canvas.setGeometry',{geometry}).catch(this.context.problem);}
  selection(ids){if(this.active&&!this.applying)this.command('canvas.select',{ids}).catch(this.context.problem);}
  async poll(){if(this.stopped)return;const serial=this.serial;try{await this.list();await this.context.refreshMapReports?.(this.sessions);if(this.active&&serial===this.serial){const id=this.session.viewSessionID,result=await this.context.rpc('canvas.get',{viewSessionID:id});if(this.active&&serial===this.serial&&this.session.viewSessionID===id&&result.revision>this.session.revision)this.present(result);}}catch(error){if(serial===this.serial)this.context.problem(error);}finally{if(!this.stopped)this.pollTimer=setTimeout(()=>this.poll(),1000);}}
};
