/* Declarative external data. No Provider markup, URLs, commands or scripts are evaluated. */
'use strict';
(() => {
  const node=(tag,value,cls)=>{const e=document.createElement(tag);if(value!==undefined)e.textContent=String(value);if(cls)e.className=cls;return e;};
  const json=value=>typeof value==='string'?value:JSON.stringify(value,null,2);
  const button=(label,run,disabled=false)=>{const e=node('button',label);e.type='button';e.disabled=disabled;e.onclick=()=>{try{return Promise.resolve(run()).catch(error=>window.alert(error.message));}catch(error){window.alert(error.message);}};return e;};
  window.ArchitectureExtensionUI=class {
    constructor(context){
      this.context=context;this.serial=0;this.data={registrations:[],publications:[],actions:[]};
      const toggle=document.getElementById('extensions-toggle');
      this.panel=node('dialog',undefined,'extension-panel');this.panel.setAttribute('aria-label','External extensions');
      const head=node('div',undefined,'extension-heading');head.append(node('h2','Extensions'),button('Close',()=>this.panel.close()));
      this.body=node('div',undefined,'extension-content');this.panel.append(head,this.body);document.body.append(this.panel);
      if(toggle)toggle.onclick=async()=>{this.body.replaceChildren(node('p','Loading extensions…'));this.panel.showModal();await this.context.paint?.();this.refresh().catch(error=>this.notice(error));};
    }
    notice(error){this.body.prepend(node('p',error.message,'extension-error'));}
    async mutate(method,params){
      if(this.context.saved)throw Error('Saved snapshot: external actions are disabled.');
      const context=await this.context.rpc('host.context');
      const response=await fetch('/extensions',{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/json','Authorization':'Bearer '+context.csrf},body:JSON.stringify({method,params})});
      const value=await response.json();if(!response.ok||value.error)throw Error(value.error?.code+': '+value.error?.message||'Extension request failed');return value;
    }
    async refresh(){
      const serial=++this.serial,view=this.context.view();if(!view)return;
      if(this.context.saved){this.data=view.extensions?.['aex-1.3']||{registrations:[],publications:[],actions:[]};this.pending=[];this.render();return;}
      const [data,pending]=await Promise.all([this.context.rpc('extensions.view',{snapshotID:view.snapshotID}),this.context.rpc('extensions.pending')]);
      if(serial!==this.serial||view!==this.context.view())return;
      const index=new Map();
      this.collectNodeAccessories(index,view,data);
      let cursor=data.nextCursor;
      while(cursor){
        const page=await this.context.rpc('extensions.view',{snapshotID:view.snapshotID,cursor});
        if(serial!==this.serial||view!==this.context.view())return;
        this.collectNodeAccessories(index,view,page);
        cursor=page.nextCursor;
      }
      this.nodeAccessories=index;
      this.data=data;this.pending=pending;this.modelPage=data;this.modelView=view;this.render();this.updateModels();
    }
    collectNodeAccessories(index,view,page){
      const model=window.ArchitectureCanvasModel;
      for(const publication of page.publications||[]){
        const binding=publication.binding;
        if(publication.applicability!=='unknown'||binding.workspaceID!==view.workspaceID||binding.snapshotID!==view.snapshotID)continue;
        const {contributions,...origin}=publication;
        for(const annotation of contributions){
          const subject=annotation.binding,conditions=annotation.data?.attributes?.conditions;
          if(annotation.kind!=='annotation'||subject?.workspaceID!==binding.workspaceID||
            subject.snapshotID!==binding.snapshotID||!subject.inputManifestDigest||subject.inputManifestDigest!==binding.inputManifestDigest)continue;
          const items=[];
          const custom=annotation.data?.attributes?.nodeAccessory;
          if(custom&&['info','flag','bookmark'].includes(custom.icon)&&['accent','neutral'].includes(custom.tone)&&
             typeof custom.label==='string'&&custom.label.trim()&&custom.label.length<=80){
            items.push({origin,annotation,icon:custom.icon,tone:custom.tone,label:custom.label.trim()});
          }
          for(const condition of Array.isArray(conditions)?conditions:[]){
            const backend=model.conditionBackend(condition);
            if(!backend)continue;
            const [label,tone,symbol]=model.conditionVerdict(condition.outcome);
            items.push({origin,annotationID:annotation.id,condition,backend,label,tone,symbol});
          }
          if(!items.length)continue;
          for(const id of subject.entityIDs){
            if(!binding.entityIDs.includes(id))continue;
            if(!index.has(id))index.set(id,[]);
            index.get(id).push(...items);
          }
        }
      }
    }
    async openNodeAccessory(entityID,result,active){
      const valid=()=>active()&&this.nodeAccessories?.get(entityID)?.includes(result);
      if(!valid())return;
      if(result.annotation){
        this.showContribution(result.label,result.origin,result.annotation);
        return;
      }
      const model=window.ArchitectureCanvasModel;
      const [graph]=model.conditionGraphs({id:result.annotationID,kind:'annotation',data:{attributes:{conditions:[result.condition]}}});
      await this.context.onCanvas(graph.data,result.origin,graph.id,valid,async()=>(await model.readConditionCall(graph,this.context.rpc,result.origin.binding.snapshotID)).data);
    }
    prepareModelAction(view,entity,model){
      const registration=model.registration,definition=registration.manifest.actions.find(a=>a.inputSchemaID===(model.project?'invar.verify-project.v1':'invar.verify-model.v2'));
      return this.mutate('actions.prepare',{registrationID:registration.id,actionID:definition.id,arguments:model.project?{configuration:model.specification}:model.specification?{specification:model.specification}:{},binding:{workspaceID:view.workspaceID,snapshotID:view.snapshotID,inputManifestDigest:model.inputManifestDigest,entityIDs:[entity.id],factIDs:[]}});
    }
    actionDetails(host,prepared){
      host.replaceChildren(node('p',prepared.executable),node('pre',json(prepared.intent.binding)),node('pre',json(prepared.intent.arguments)),node('p',prepared.intent.requestFingerprint));
    }
    modelCommand(host,entity,closeMenu){
      if(this.context.saved)return;
      const view=this.context.view();
      const project=['workspace','softwareSystem'].includes(entity.kind)||!!entity.attributes?.['context.owner'];
      const command=button(project?'Verify project':'Verify model',()=>this.reviewModel(view,entity,availability,command.ready,closeMenu,project));
      command.dataset.icon='stateTransition';command.title='Checking verification availability…';host.append(command);
      const availability=(project?this.projectAvailability(view,entity):this.modelAvailability(view,entity)).then(model=>{
        if(model.unavailable){command.title=model.unavailable;return model;}
        if(model.generationIntent){
          const detail=node('details',undefined,'model-authorization'),body=node('div');
          this.actionDetails(body,model.generationIntent.prepared);
          detail.append(node('summary','Generate TLA+ and Lean with Invar · Run details'),body);host.append(detail);
        }
        command.ready=true;command.title=model.specification||'Generate an unverified model from the selected implementation.';
        return model;
      });
    }
    async projectAvailability(view,entity){
      try{
        const page=await this.context.rpc('extensions.view',{snapshotID:view.snapshotID});
        const registration=(page.registrations||[]).find(r=>r.connected&&!r.disabled&&r.permissions.includes('actions.receive')&&r.manifest.actions.some(a=>a.inputSchemaID==='invar.verify-project.v1'));
        if(!registration)return {unavailable:'Connect an Invar provider with project verification support.'};
        const {manifest,inputManifestDigest}=await this.context.rpc('inputs.manifest',{snapshotID:view.snapshotID});
        const path=entity.anchor?.path||'',directory=path.includes('/')?path.slice(0,path.lastIndexOf('/')+1):'';
        const specification=directory+'Verification/Project/invar.json';
        if(!manifest.files[specification])return {unavailable:'Configure the project verification workflow at '+specification+'.'};
        return {registration,inputManifestDigest,specification,project:true};
      }catch(error){return {unavailable:error.message};}
    }
    async modelAvailability(view,entity){
      try{
        const page=this.modelView===view?this.data:await this.context.rpc('extensions.view',{snapshotID:view.snapshotID});
        const registration=(page.registrations||[]).find(r=>r.connected&&!r.disabled&&r.permissions.includes('actions.receive')&&r.manifest.actions.some(a=>a.inputSchemaID==='invar.verify-model.v2'));
        if(!registration){return {unavailable:'Connect Invar to open the model.'};}
        if(this.manifestSnapshot!==view.snapshotID){
          this.manifestSnapshot=view.snapshotID;
          this.manifestPromise=this.context.rpc('inputs.manifest',{snapshotID:view.snapshotID});
          this.manifestPromise.catch(()=>{if(this.manifestSnapshot===view.snapshotID)this.manifestSnapshot=null;});
        }
        const {manifest,inputManifestDigest}=await this.manifestPromise;
        let specification='Verification/'+entity.id+'/properties.json';
        if(!manifest.files[specification]){
          const named='Verification/'+entity.name+'/properties.json';
          const kinds=['type','function','method','field','extension','protocol'];
          specification=null;
          if(kinds.includes(entity.kind)&&!entity.name.includes('/')&&manifest.files[named]){
            const matches=await this.context.rpc('graph.search',{snapshotID:view.snapshotID,text:entity.name,limit:200});
            if(matches.nodes.some(n=>n.name===entity.name&&kinds.includes(n.kind)&&n.id!==entity.id)){
              return {unavailable:'Use the node ID to distinguish declarations with the same name.'};
            }
            specification=named;
          }
          const swiftSelection=entity.language==='swift'&&['type','actor','method','extension','field'].includes(entity.kind);
          if(!specification&&!swiftSelection&&!['file','function'].includes(entity.kind)){
            return {unavailable:'Select an implementation file, free function or supported Swift declaration.'};
          }
        }
        const model={registration,specification,inputManifestDigest};
        if(!specification){
          const existing=(page.publications||[]).some(p=>p.providerID===registration.providerID&&p.applicability==='unknown'&&p.binding.workspaceID===view.workspaceID&&p.binding.snapshotID===view.snapshotID&&p.binding.inputManifestDigest===inputManifestDigest&&p.binding.entityIDs.length===1&&p.binding.entityIDs[0]===entity.id&&p.contributions.some(c=>c.data?.metadata?.modelStatus==='generatedUnverified'));
          if(!existing){
            // A menu may be reopened repeatedly within the host's bounded confirmation window.
            const key=JSON.stringify([registration.id,view.workspaceID,view.snapshotID,inputManifestDigest,entity.id]);
            this.draftIntents??=new Map();
            for(const [id,entry] of this.draftIntents)if(entry.intent.deadline<=Date.now()/1000)this.draftIntents.delete(id);
            const prepared=this.draftIntents.get(key)||await this.prepareModelAction(view,entity,model);
            this.draftIntents.set(key,prepared);
            model.generationIntent={key,prepared};
          }
        }
        return model;
      }catch(error){return {unavailable:error.message};}
    }
    closeModel(){
      if(!this.review)return;
      clearTimeout(this.review.timer);
      this.review.panel.remove();
      this.review=null;
    }
    async verificationResult(review,requestID){
      const {view,entity,model}=review;
      const bound=b=>b?.workspaceID===view.workspaceID&&b.snapshotID===view.snapshotID&&b.inputManifestDigest===model.inputManifestDigest&&b.entityIDs.length===1&&b.entityIDs[0]===entity.id;
      let cursor,job,attempt,publication;
      do{
        const page=await this.context.rpc('extensions.view',{snapshotID:view.snapshotID,...(cursor?{cursor}:{})});
        if(this.review!==review)return {};
        if(requestID)job||=(page.actions||[]).find(a=>a.requestID===requestID&&a.providerID===model.registration.providerID&&a.actionID===(model.project?'verify-project':'verify-model')&&bound(a.binding));
        for(const p of page.publications||[]){
          const draft=p.contributions?.some(c=>c.data?.metadata?.modelStatus==='generatedUnverified');
          if((requestID||draft===!model.specification)&&p.providerID===model.registration.providerID&&bound(p.binding)&&p.applicability==='unknown'&&(!requestID||job?.runID===p.runID)&&(!publication||publication.generation<p.generation))publication=p;
        }
        if(job?.runID)attempt||=(page.attempts||[]).find(a=>a.runID===job.runID);
        cursor=page.nextCursor;
      }while(cursor&&!publication);
      return {job,publication,attempt};
    }
    async expressionLabels(graph,review){
      const nodes=graph.data.nodes.slice(),anchor=review.entity.anchor;
      // Source text is resolved by the authorized snapshot reader only when opening the model.
      for(let start=0;start<nodes.length;start+=4){
        if(this.review!==review)return graph;
        await Promise.all(nodes.slice(start,start+4).map(async(n,index)=>{
          const a=n.attributes;
          if(!anchor||a?.sourceDigest!==anchor.digest||!Number.isSafeInteger(a.sourceStart)||!Number.isSafeInteger(a.sourceEnd)||
            a.sourceStart<anchor.startByte||a.sourceEnd>anchor.endByte||a.sourceEnd<=a.sourceStart||a.sourceEnd-a.sourceStart>512)return;
          let reply;
          try{reply=await this.context.rpc('source.read',{snapshotID:review.view.snapshotID,entityID:review.entity.id,startByte:a.sourceStart,endByte:a.sourceEnd});}
          catch{nodes[start+index]={...n,label:n.label+' · Source unavailable'};return;}
          if(reply.truncated||reply.snapshotID!==review.view.snapshotID||reply.anchor?.digest!==anchor.digest||
              reply.anchor.path!==anchor.path||reply.anchor.startByte!==a.sourceStart||reply.anchor.endByte!==a.sourceEnd)return;
          nodes[start+index]={...n,label:n.label.split(' · ')[0]+' · '+reply.text.trim()};
        }));
      }
      return {...graph,data:{...graph.data,nodes}};
    }
    verificationStatus(review,message,level='info'){
      if(this.review!==review||review.status.textContent===message)return;
      review.status.textContent=message;
      this.context.onVerificationStatus?.(message);
      this.context.log?.(level,review.entity.name+' · '+message);
    }
    async showVerificationGraphs(review,publication){
      const order=['counterexample','tlaStateSpace','tlaSpecification','leanProofTerm','leanDeclarations'];
      const conditions=publication.contributions.filter(c=>c.binding.entityIDs.includes(review.entity.id)).flatMap(c=>window.ArchitectureCanvasModel.conditionGraphs(c));
      const structural=publication.contributions.filter(c=>c.kind==='graph'&&c.binding.entityIDs.includes(review.entity.id)&&order.includes(c.data.metadata?.formalKind)&&c.data.nodes?.length)
        .sort((a,b)=>order.indexOf(a.data.metadata.formalKind)-order.indexOf(b.data.metadata.formalKind));
      const projects=review.project?publication.contributions.filter(c=>c.kind==='graph'&&c.binding.entityIDs.includes(review.entity.id)&&c.data.metadata?.verificationReport&&c.data.nodes?.length):[];
      const graphs=[...projects,...conditions,...structural];
      if(!graphs.length)return false;
      const selector=review.selector;
      selector.replaceChildren();
      const draft=structural.find(graph=>graph.data.metadata.modelStatus==='generatedUnverified');
      review.modelSummary=projects.length?window.ArchitectureCanvasModel.specificationReport(projects[0].data).summary.title:draft?.data.metadata.producer==='swift-formal/swift-expression-v1'?'Partial model · Whole node unverified':'Unverified · No verification conditions';
      for(const graph of graphs){
        const option=node('option',window.ArchitectureCanvasModel.formalModel(graph.data)?.title||graph.data.title);
        option.value=graph.id;selector.append(option);
      }
      selector.hidden=false;
      const open=async graph=>{
        const active=()=>this.review===review&&selector.value===graph.id&&review.publication===publication;
        if(!active())return;
        review.condition=graph.data.metadata.formalKind==='verificationCondition'?graph.data.title:null;
        await this.context.onCanvas(graph.data,publication,graph.id,active,async()=>{
          const display=graph.data.metadata.producer==='swift-formal/swift-expression-v1'?await this.expressionLabels(graph,review):await window.ArchitectureCanvasModel.readConditionCall(graph,this.context.rpc,review.view.snapshotID);
          return display.data;
        });
      };
      review.publication=publication;
      const selected=projects[0]||conditions.find(g=>g.data.title===review.condition)||conditions[0]||draft||structural[0];
      selector.value=selected?.id||'';
      selector.onchange=()=>open(graphs.find(g=>g.id===selector.value)).catch(error=>{this.verificationStatus(review,error.message,'error');});
      if(selected)await open(selected);
      return !!selected;
    }
    async followVerification(review,requestID){
      if(this.review!==review)return;
      try{
        const {job,publication,attempt}=await this.verificationResult(review,requestID);
        if(this.review!==review)return;
        if(publication){
          try{
            const shown=await this.showVerificationGraphs(review,publication);
            this.verificationStatus(review,shown?(review.project?review.modelSummary:review.model.specification?'Latest verification result':review.modelSummary):review.publication?'No condition evidence for this run.':'This run published no TLA+ or Lean graph.');
          }catch(error){this.verificationStatus(review,error.message,'error');}
          return;
        }
        if(['failed','cancelled','rejected','expired'].includes(job?.state)||
           attempt&&attempt.completion!=='pending'){
          this.modelUnavailable(review,attempt?.diagnostic||job?.receipt?.reason||'The provider ended the run without publishing a graph ('+(attempt?.completion||job.state)+').');
          return;
        }
        this.verificationStatus(review,job?.state==='completed'?'Waiting for the graph…':review.project?'Verifying specification, implementation and correspondence…':review.model.specification?'Verifying…':'Generating model…');
      }catch(error){this.verificationStatus(review,error.message,'error');}
      if(this.review===review)review.timer=setTimeout(()=>this.followVerification(review,requestID),2000);
    }
    modelUnavailable(review,reason){
      review.panel.dataset.state='unavailable';
      this.verificationStatus(review,reason,'error');
      review.heading.textContent=review.project?'Project verification unavailable':'Model unavailable';
      if(!review.retry){review.retry=button('Retry',()=>this.reviewModel(review.view,review.entity,null,false,()=>{},review.project));review.panel.append(review.retry);}
    }
    async reviewModel(view,entity,availability,readyAtClick,closeMenu,project=false){
      if(view!==this.context.view())return;
      closeMenu();this.closeModel();
      const panel=node('section',undefined,'verification-review');
      panel.setAttribute('aria-label',project?'Verify project':'Verify model');
      const bar=node('div',undefined,'verification-bar'),selector=node('select'),status=node('span',project?'Preparing project verification…':'Loading model…');
      selector.hidden=true;selector.setAttribute('aria-label','Verification graph');status.setAttribute('role','status');
      const detail=node('details'),close=button('×',()=>{
        if(panel.dataset.presentation==='graph'){document.getElementById('model-info').hidePopover();return;}
        if(this.context.leaveVerification)this.context.leaveVerification();else this.closeModel();
      });
      close.setAttribute('aria-label','Close');
      const heading=node('strong',entity.name.split('/').pop());
      const review={view,entity,panel,selector,status,heading,project};
      this.review=review;
      this.context.log?.('info',entity.name+' · Opening verification model.');
      const authorization=node('div');
      const prepare=async()=>{
        prepared=await this.prepareModelAction(view,entity,model);
        this.actionDetails(authorization,prepared);
      };
      const submit=async()=>{
        confirm.disabled=true;
        this.verificationStatus(review,project?'Submitting project verification…':'Submitting verification…');
        try{
          if(!submitted&&prepared.intent.deadline<=Date.now()/1000){
            await prepare();detail.open=true;confirm.hidden=false;confirm.disabled=false;
            this.verificationStatus(review,'The request was updated. Review the details before running it.');
            return;
          }
          submitted=true;
          if(model.generationIntent)this.draftIntents.delete(model.generationIntent.key);
          await this.mutate('actions.confirm',{token:prepared.intent.authorizationToken,requestFingerprint:prepared.intent.requestFingerprint});
          if(this.review!==review)return;
          detail.open=false;confirm.hidden=true;
          await this.followVerification(review,prepared.intent.requestID);
        }catch(error){this.verificationStatus(review,error.message,'error');confirm.hidden=false;confirm.disabled=false;}
      };
      const confirm=button('Run verification',submit,true);
      confirm.hidden=true;
      bar.append(heading,selector,status,confirm,close);
      const subject=node('code',entity.anchor?.path||entity.name,'model-source');
      detail.hidden=true;panel.append(bar,subject,detail);document.getElementById('canvas-tools').after(panel);
      panel.dataset.presentation='pending';
      await this.context.enterVerification?.(view,entity,project);
      if(this.review!==review)return;
      const model=await (availability||(project?this.projectAvailability(view,entity):this.modelAvailability(view,entity)));
      if(this.review!==review)return;
      if(view!==this.context.view()){this.modelUnavailable(review,'The source view changed. Reopen Verify model on the current selection.');return;}
      if(model.unavailable){this.modelUnavailable(review,model.unavailable);return;}
      review.model=model;
      confirm.textContent=model.specification?'Run verification':'Generate model';
      let prepared=model.generationIntent?.prepared,submitted=false;
      detail.hidden=false;detail.append(node('summary','Run details'),node('code',model.specification||entity.anchor?.path||entity.name),node('p','Snapshot '+view.snapshotID),authorization);
      try{
        if(project){
          await prepare();
          this.verificationStatus(review,'Ready to verify specification, implementation and correspondence.');
          confirm.hidden=false;confirm.disabled=false;return;
        }
        const {publication}=await this.verificationResult(review);
        if(this.review!==review)return;
        const shown=publication&&await this.showVerificationGraphs(review,publication);
        if(this.review!==review)return;
        if(!model.specification&&shown){this.verificationStatus(review,review.modelSummary);confirm.hidden=true;return;}
        if(!publication&&prepared){
          this.actionDetails(authorization,prepared);
          if(readyAtClick)await submit();
          else{
            this.verificationStatus(review,'Ready to generate TLA+ and Lean.');
            confirm.hidden=false;confirm.disabled=false;
          }
          return;
        }
        this.verificationStatus(review,shown?(model.specification?'Published result':review.modelSummary):publication?'No condition evidence is available.':model.specification?'Run verification to see the graph.':'No verification conditions. Generate a model from this implementation.');
      }catch(error){this.verificationStatus(review,error.message,'error');}
      if(this.review!==review)return;
      try{
        await prepare();
        confirm.hidden=false;confirm.disabled=false;
      }catch(error){this.verificationStatus(review,error.message,'error');}
    }
    modelSlot(host,filter,onCount){
      if(this.context.saved)return;
      const slot=node('div',undefined,'formal-models');
      host.append(slot);
      this.slots=(this.slots||[]).filter(item=>item.slot.isConnected);
      const item={slot,filter,onCount,view:this.context.view()};
      this.slots.push(item);
      if(this.modelView===item.view)this.fillModels(item,this.modelPage);
    }
    updateModels(){
      this.slots=(this.slots||[]).filter(item=>item.slot.isConnected);
      for(const item of this.slots)if(item.view===this.modelView)this.fillModels(item,this.modelPage);
      this.context.onPublicationsChanged?.();
    }
    *menuItems(view,page,filter={}){
      for(const publication of page.publications||[]){
        if(publication.applicability!=='unknown'||publication.binding.snapshotID!==view.snapshotID||publication.binding.workspaceID!==view.workspaceID)continue;
        for(const contribution of publication.contributions){
          const graph=contribution.kind==='graph'||(contribution.kind==='view'&&contribution.data.kind==='graph');
          const model=graph&&window.ArchitectureCanvasModel.formalModel(contribution.data);
          const report=graph&&contribution.data.metadata?.verificationReport;
          if(filter.projectOnly&&!report)continue;
          if(!model&&!report&&!filter.nodeMenu&&!(filter.entity&&contribution.kind==='annotation'))continue;
          if(filter.entity&&!contribution.binding.entityIDs.includes(filter.entity))continue;
          if(filter.fact&&!contribution.binding.factIDs.includes(filter.fact))continue;
          const label=contribution.data.title||contribution.data.claim;
          const title=model?.title||(typeof label==='string'&&label.trim())||contribution.id;
          if(filter.text&&!title.toLowerCase().includes(filter.text.toLowerCase()))continue;
          const icon=model?.kind||(graph?'relations':contribution.data.kind==='table'?'table':'document');
          yield {title,icon,graph,publication,contribution};
        }
      }
    }
    fillModels(item,page){
      const {slot,view,filter}=item;
      slot.replaceChildren();
      if(filter.entity&&!filter.nodeMenu){
        for(const job of this.data.actions||[]){
          if(job.actionID==='verify-model'&&job.binding?.snapshotID===view.snapshotID&&job.binding.entityIDs.includes(filter.entity))
            slot.append(node('p','Verify model · '+job.state+(job.receipt?.reason?' · '+job.receipt.reason:'')));
        }
      }
      const links=node('div',undefined,'action-row');
      for(const {title,icon,graph,publication,contribution} of this.menuItems(view,page,filter)){
        const open=button(title,()=>{
          if(graph)return this.context.onCanvas(contribution.data,publication,contribution.id);
          this.showContribution(title,publication,contribution);
        });
        open.dataset.icon=icon;open.title=publication.provider+' · '+contribution.id;links.append(open);
        if(filter.entity&&!filter.nodeMenu&&contribution.kind==='annotation'){
          const report=contribution.data;
          const summary=[report.reportedStatus,report.scope,report.translationStatus&&'Translation: '+report.translationStatus].filter(Boolean);
          if(summary.length)links.append(node('p',summary.join(' · ')));
        }
      }
      item.onCount?.(links.childNodes.length);
      if(links.childNodes.length){
        if(!filter.nodeMenu)slot.append(node('h3',filter.projectOnly?'Project verification':filter.entity?'Published evidence':filter.text?'Models':'Open model'));
        slot.append(links);
      }
      if(page.nextCursor)slot.append(button('More published models…',async()=>{
        const serial=this.serial;
        const next=await this.context.rpc('extensions.view',{snapshotID:view.snapshotID,cursor:page.nextCursor});
        if(serial!==this.serial||!slot.isConnected||page!==this.modelPage)return;
        this.modelPage={publications:[...page.publications,...next.publications],nextCursor:next.nextCursor};
        this.updateModels();
      }));
    }
    render(){
      const fragment=document.createDocumentFragment(),saved=this.context.saved;
      fragment.append(node('p',saved?'Saved snapshot · not live · external actions disabled':'External results are Provider reports. Input applicability and core evidence are separate.','subtle'));
      for(const pending of this.pending||[]){
        const section=node('section',undefined,'extension-section');section.append(node('h3','Approval requested · '+pending.manifest.displayName),node('p',pending.peer.executable),node('code','SHA-256 '+pending.peer.binaryDigest),node('p','Profile: '+pending.manifest.specificationProfiles.join(', ')));
        const choices=[];
        for(const permission of pending.manifest.requestedPermissions){const label=node('label',undefined,'extension-permission'),input=node('input');input.type='checkbox';input.checked=true;label.append(input,node('span',permission));section.append(label);choices.push([permission,input]);}
        section.append(button('Approve selected permissions',async()=>{await this.mutate('extensions.approve',{id:pending.id,permissions:choices.filter(([,input])=>input.checked).map(([permission])=>permission)});await this.refresh();},saved));fragment.append(section);
      }
      for(const registration of this.data.registrations||[]){
        const section=node('section',undefined,'extension-section'),manifest=registration.manifest;
        section.append(node('h3',manifest.displayName+' · '+manifest.version),node('p',saved?'Saved registration · not connected':registration.disabled?'Disabled':registration.connected?'Connected':'Provider disconnected'),node('p',registration.executable,'subtle'));
        const actions=node('div',undefined,'action-row');
        for(const definition of manifest.actions){
          if(definition.inputSchemaID==='invar.verify-model.v2')continue;
          actions.append(button(definition.title,()=>this.action(registration,definition),saved||!registration.connected||!registration.permissions.includes('actions.receive')));
        }
        actions.append(button('Disable',async()=>{await this.mutate('extensions.unregister',{id:registration.id});await this.refresh();},saved||registration.disabled));section.append(actions);fragment.append(section);
      }
      for(const publication of this.data.publications||[]){
        const section=node('section',undefined,'extension-section');section.dataset.publicationId=publication.publicationID;
        section.append(node('h3',publication.provider+' · '+publication.providerVersion),node('p','Input applicability: '+publication.applicability),node('p','Run '+publication.runID+' · publication '+publication.publicationID,'subtle'),node('p','Snapshot '+publication.binding.snapshotID,'subtle'));
        for(const contribution of publication.contributions)this.contribution(section,contribution,publication);
        fragment.append(section);
      }
      if((this.data.actions||[]).length){
        const section=node('section',undefined,'extension-section');section.append(node('h3','External jobs'));
        for(const job of this.data.actions)section.append(node('p',job.providerID+' / '+job.actionID+' · '+job.state+' · last observed '+job.lastObserved));fragment.append(section);
      }
      const attempts=(this.data.attempts||[]).filter(a=>a.completion!=='complete');
      if(attempts.length){const section=node('section',undefined,'extension-section');section.append(node('h3','Attempts · previous complete result retained'));for(const attempt of attempts)section.append(node('p',attempt.runID+' · '+attempt.completion));fragment.append(section);}
      if(!fragment.childNodes.length)fragment.append(node('p','No external extensions.'));
      if(this.data.nextCursor)fragment.append(button('Next external results',async()=>{const view=this.context.view(),cursor=this.data.nextCursor;this.body.replaceChildren(node('p','Loading external results…'));try{await this.context.paint?.();if(view!==this.context.view())return;const data=await this.context.rpc('extensions.view',{snapshotID:view.snapshotID,cursor});if(view!==this.context.view())return;this.data=data;this.render();}catch(error){this.notice(error);}},saved));
      this.body.replaceChildren(fragment);
    }
    showContribution(title,publication,contribution){
      const dialog=node('dialog',undefined,'extension-panel');
      dialog.setAttribute('aria-label',title);
      const heading=node('div',undefined,'extension-heading');
      heading.append(node('h2',title),button('Close',()=>dialog.close()));
      const content=node('div',undefined,'extension-content');
      content.append(node('p',publication.provider+' · '+publication.publicationID,'subtle'));
      this.contribution(content,contribution,publication,dialog);
      dialog.append(heading,content);document.body.append(dialog);
      dialog.addEventListener('close',()=>dialog.remove(),{once:true});dialog.showModal();
    }
    contribution(section,contribution,publication,dialog=this.panel){
      const data=contribution.data,box=node('div',undefined,'extension-contribution');box.dataset.contributionId=contribution.id;
      box.append(node('h4',contribution.id));
      if(contribution.kind==='annotation'){
        box.append(node('p','Reported status: '+data.reportedStatus),node('p',data.claim),node('p','Scope: '+(data.scope||json(contribution.binding.entityIDs))),node('p','Assumptions: '+json(data.assumptions||[])),node('p','Translation: '+(data.translationStatus||'unknown')));
      }else if(contribution.kind==='graph'||data.kind==='graph'){this.graph(box,data,publication,contribution.id,dialog);}
      else if(data.kind==='table'){
        const table=node('table'),head=node('tr');for(const column of data.columns||[])head.append(node('th',typeof column==='string'?column:column.title));table.append(head);
        for(const row of (data.rows||[]).slice(0,256)){const tr=node('tr');for(const cell of (Array.isArray(row)?row:Object.values(row)).slice(0,32))tr.append(node('td',json(cell)));table.append(tr);}box.append(table);
      }else if(data.kind==='keyValue'){
        const list=node('dl');for(const [key,value] of Object.entries(data.values||{}).slice(0,128))list.append(node('dt',key),node('dd',json(value)));box.append(list);
      }else if(data.kind==='timeline'){
        const list=node('ol');for(const item of (data.items||[]).slice(0,256))list.append(node('li',(item.time||'')+' '+(item.label||json(item))));box.append(list);
      }else if(data.kind==='artifactList'){
        for(const artifact of (data.artifacts||[]).slice(0,128))box.append(node('p',artifact.path+' · SHA-256 '+artifact.digest));
        box.append(node('p','Artifact references only; contents are not fetched.','subtle'));
      }else if(data.kind==='overlay'){
        for(const item of (data.items||[]).slice(0,256))box.append(node('p',(item.entityID||item.factID||'Unbound')+' · '+(item.label||json(item))));
      }else box.append(node('p',data.text||json(data)));
      for(const id of contribution.binding.entityIDs.slice(0,16))box.append(button('Source · '+id.slice(0,11)+'…',()=>{dialog.close();this.context.onNavigate(id,publication.binding.snapshotID);},this.context.saved||publication.applicability==='unmatched'));
      section.append(box);
    }
    graph(box,data,publication,id,dialog=this.panel){
      box.append(node('p',`${(data.nodes||[]).length} nodes · ${(data.edges||[]).length} relations`));
      box.append(button('Open in Canvas',()=>{dialog.close();return this.context.onCanvas(data,publication,id);},this.context.saved||!this.context.onCanvas));
      const list=node('details');list.append(node('summary','External graph identities and relations'));for(const edge of data.edges||[])list.append(node('p',edge.source+' → '+edge.target+' · '+(edge.kind||edge.role||'unknown')));box.append(list);
    }
    async action(registration,definition){
      const target=definition.operation==='cancel'?(this.data.actions||[]).find(job=>job.providerID===registration.providerID&&job.receipt?.jobID&&job.runID&&!['completed','failed','cancelled','rejected','expired'].includes(job.state)):null;
      const dialog=node('dialog',undefined,'extension-confirmation');dialog.setAttribute('aria-label',definition.title);dialog.append(node('h2',definition.title),node('p','Provider: '+registration.manifest.displayName),node('p','Arguments must match '+definition.inputSchemaID));
      const input=node('textarea');input.setAttribute('aria-label','Typed arguments as JSON');input.value=target?JSON.stringify({requestID:target.requestID,jobID:target.receipt.jobID,runID:target.runID},null,2):'{}';dialog.append(input);
      const detail=node('div');dialog.append(detail);let prepared;
      const confirm=button('Confirm external execution',async()=>{if(!prepared)return;confirm.disabled=true;try{await this.mutate('actions.confirm',{token:prepared.intent.authorizationToken,requestFingerprint:prepared.intent.requestFingerprint});dialog.close();await this.refresh();}catch(error){detail.append(node('p',error.message));confirm.disabled=false;}},true);
      const prepare=button('Review execution',async()=>{
        const view=this.context.view(),selected=this.context.selection();if(!view)throw Error('No input snapshot selected.');
        const manifest=await this.context.rpc('inputs.manifest',{snapshotID:view.snapshotID});
        prepared=await this.mutate('actions.prepare',{registrationID:registration.id,actionID:definition.id,arguments:JSON.parse(input.value),binding:target?target.binding:{workspaceID:view.workspaceID,snapshotID:view.snapshotID,inputManifestDigest:manifest.inputManifestDigest,entityIDs:selected?[selected.id]:[],factIDs:[]}});
        input.disabled=true;prepare.disabled=true;detail.replaceChildren(node('p','External code may run in the Provider-owned environment.'),node('p',prepared.executable),node('pre',json(prepared.intent.binding)),node('pre',json(prepared.intent.arguments)),node('p','Fingerprint: '+prepared.intent.requestFingerprint));confirm.disabled=false;
      });
      dialog.append(prepare,confirm,button('Cancel',()=>dialog.close()));dialog.addEventListener('close',()=>dialog.remove());document.body.append(dialog);dialog.showModal();
    }
  };
})();
