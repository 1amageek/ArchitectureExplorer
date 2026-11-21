/* Pure projections for imported diagrams; source facts are never rewritten. */
(function(scope){
  'use strict';
  const kinds=['hierarchy','relations','controlFlow','dataFlow','stateTransition','sequence','proofDependencies'];
  const escape=value=>String(value??'').replace(/[&<>"']/g,char=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[char]));
  const formalKinds=new Map([
    ['verificationCondition',['Verification condition','relations']],
    ['tlaSpecification',['TLA+ specification','relations']],
    ['tlaStateSpace',['TLA+ state space','stateTransition']],
    ['counterexample',['TLA+ counterexample','stateTransition']],
    ['leanDeclarations',['Lean declarations','proofDependencies']],
    ['leanProofTerm',['Lean proof term','proofDependencies']],
    ['irControlFlow',['IR control flow','controlFlow']]
  ]);
  function formalModel(data){
    const spec=formalKinds.get(data?.metadata?.formalKind);
    if(!spec)return null;
    const name=typeof data.title==='string'&&data.title.trim()||data.nodes?.find(n=>n.attributes?.isDeclaredRoot&&n.label)?.label;
    const title=name?spec[0]+' · '+name:spec[0];
    return {title:data.metadata.modelStatus==='generatedUnverified'?title+' · Unverified':title,kind:spec[1]};
  }
  // Read the complete document so the verdict survives filtering and collapsed nodes.
  function verificationSummary(document){
    const meta=document.metadata?.providerMetadata;
    if(!formalKinds.has(meta?.formalKind))return null;
    const condition=meta.formalKind==='verificationCondition';
    const draft=meta.modelStatus==='generatedUnverified';
    const backend=condition?new Map([['generatedModel.lean.quantified','Lean'],['generatedModel.lean.finite','Lean'],
      ['generatedModel.tla.finite','TLA+']]).get(meta.domain):
      new Map([['leanDeclarations','Lean'],['leanProofTerm','Lean'],['tlaSpecification','TLA+'],
        ['tlaStateSpace','TLA+'],['counterexample','TLA+']]).get(meta.formalKind);
    if(!backend)return null;
    const result={backend,title:'Model structure',tone:'neutral',symbol:'◇',subject:'',formula:'',scope:'',translation:''};
    const translation=String(meta.translation||'').toLowerCase();
    result.translation=translation==='validated'?'Equivalence to source validated':translation==='unvalidated'?'Equivalence to source not validated':
      translation==='mismatch'?'Translation differs from source':'Equivalence to source unknown';
    if(condition){
      const root=document.nodes.find(n=>n.role==='Verification condition'&&meta.claimID&&meta.bundleID&&n.details?.claimID===meta.claimID&&n.details?.bundleID===meta.bundleID);
      const outcome=root&&root.details.outcome===meta.outcome?meta.outcome:null;
      [result.title,result.tone,result.symbol]=conditionVerdict(outcome);
      result.subject=root?.label||'Verification condition';
      result.formula=document.nodes.find(n=>['Postcondition','Expected termination'].includes(n.role))?.label||'';
      result.scope=root?.details.scope||'';
    }else if(draft){
      result.title='Unverified';result.symbol='−';result.subject='No verification conditions';
      if(meta.producer==='swift-formal/swift-expression-v1'){
        result.title='Partial model';result.subject='Local arithmetic checks and abstract branches';
        result.scope='Assumes standard 64-bit Swift integers and collection counts. Framework calls and rendering are outside scope.';
      }
    }else{
      result.title=formalKinds.get(meta.formalKind)[0];
      result.subject='Model evidence';
    }
    return result;
  }
  const verdicts=new Map([['proved',['Proved','positive','✓']],['modelChecked',['Model checked','positive','✓']],
    ['counterexample',['Counterexample','negative','!']],['unproved',['Unproved','neutral','?']]]);
  const conditionVerdict=outcome=>verdicts.get(outcome)||['Inconclusive','neutral','?'];
  function conditionBackend(condition){
    if(!condition||!['claimID','bundleID','name','entry','domain','outcome','scope','translation'].every(k=>typeof condition[k]==='string'&&condition[k]))return null;
    if(condition.domain==='generatedModel.lean.quantified')return typeof condition.requires==='string'&&typeof condition.ensures==='string'?'Lean':null;
    if(typeof condition.expectedStatus!=='string')return null;
    if(condition.domain==='generatedModel.lean.finite')return 'Lean';
    return condition.domain==='generatedModel.tla.finite'?'TLA+':null;
  }
  function conditionGraphs(annotation){
    const conditions=annotation.data?.attributes?.conditions;
    if(annotation.kind!=='annotation'||!Array.isArray(conditions))return [];
    const graphs=[];
    for(const condition of conditions){
      const backend=conditionBackend(condition);
      if(!backend)continue;
      const quantified=condition.domain==='generatedModel.lean.quantified';
      const id=annotation.id+'-'+condition.bundleID+'-'+condition.claimID;
      const root='obligation';
      const nodes=[{id:root,role:'Verification condition',label:condition.name,language:backend==='Lean'?'lean':'tla',
        details:{status:backend+' · '+condition.outcome,attributes:{isDeclaredRoot:true},...condition}}];
      const edges=[];
      function related(key,role,label){
        nodes.push({id:key,role,label,details:{status:role}});
        edges.push({id:'edge-'+key,source:root,target:key,role:key,label:role});
      }
      related('entry','Entry point',condition.entry);
      if(quantified){
        related('requires','Precondition',condition.requires);
        related('ensures','Postcondition',condition.ensures);
      }else related('expectedStatus','Expected termination',condition.expectedStatus);
      const metadata={formalKind:'verificationCondition',annotationID:annotation.id,claimID:condition.claimID,
        bundleID:condition.bundleID,domain:condition.domain,outcome:condition.outcome,translation:condition.translation};
      const title=condition.name+' · '+backend;
      const bindings=condition.sourceBindings;
      if(!quantified||!Array.isArray(bindings?.parameters)||!bindings.parameters.every(p=>typeof p==='string')){
        graphs.push({id,data:{title,nodes,edges,metadata}});continue;
      }
      const validSite=site=>site&&typeof site.path==='string'&&typeof site.entityID==='string'&&typeof site.digest==='string'&&
        Number.isSafeInteger(site.line)&&site.line>0&&Number.isSafeInteger(site.start)&&Number.isSafeInteger(site.end)&&
        site.start>=0&&site.end>site.start&&site.end-site.start<=16384&&Array.isArray(site.arguments)&&site.arguments.length===bindings.parameters.length;
      const sites=(Array.isArray(bindings.sites)?bindings.sites.filter(validSite):[]).sort((a,b)=>Number(b.ifCondition)-Number(a.ifCondition)||a.path.localeCompare(b.path)||a.start-b.start);
      for(const site of sites.length?sites:[null]){
        const label=site?site.path.split('/').pop()+':'+site.line:'';
        const named=nodes.map(n=>{
          if(!['requires','ensures'].includes(n.id))return n;
          const slots=new Set();
          const formula=n.label.replace(/\barg(0|[1-9]\d*)\b/g,(token,index)=>{
            if(!bindings.parameters[Number(index)])return token;
            slots.add(Number(index));
            const name=bindings.parameters[Number(index)];
            return name==='result'?'input.result':name;
          });
          if(!slots.size)return n;
          const parameters=[...slots].sort((a,b)=>a-b).map(index=>({index,name:bindings.parameters[index]}));
          return {...n,label:formula,details:{original:n.label,parameters,sourceStatus:bindings.status,
            location:label,ifCondition:site?.ifCondition,sourcePath:site?.path}};
        });
        graphs.push({id:site?id+'-'+site.entityID+'-'+site.start:id,site,
          data:{title:sites.length>1?title+' · '+label:title,nodes:named,edges,metadata}});
      }
    }
    return graphs;
  }
  async function readConditionCall(graph,rpc,snapshotID){
    const site=graph.site;
    if(!site)return graph;
    let expressions,issue;
    try{
      const reply=await rpc('source.read',{snapshotID,entityID:site.entityID,startByte:site.start,endByte:site.end});
      const anchor=reply.anchor;
      if(reply.truncated||reply.snapshotID!==snapshotID||anchor?.path!==site.path||anchor.digest!==site.digest||
          anchor.startByte!==site.start||anchor.endByte!==site.end)throw Error('Call site differs from the verified snapshot.');
      const bytes=new TextEncoder().encode(reply.text),decoder=new TextDecoder('utf-8',{fatal:true});
      if(bytes.length!==site.end-site.start)throw Error('Incomplete call site.');
      expressions=site.arguments.map(range=>{
        if(!Number.isSafeInteger(range.start)||!Number.isSafeInteger(range.end)||range.start<site.start||
            range.end>site.end||range.start>=range.end)throw Error('Invalid argument range.');
        return decoder.decode(bytes.subarray(range.start-site.start,range.end-site.start));
      });
    }catch(error){issue=error.message;}
    const nodes=graph.data.nodes.map(n=>n.details?.parameters?{...n,details:{...n.details,sourceIssue:issue,
      parameters:n.details.parameters.map(p=>({...p,expression:expressions?.[p.index]}))}}:n);
    return {...graph,id:issue?graph.id+'-unavailable':graph.id,data:{...graph.data,nodes}};
  }
  function conditionLines(node){
    const details=node.canvas?.details;
    if(!Array.isArray(details?.parameters)||!details.parameters.length||!['Precondition','Postcondition'].includes(node.canvas.role)||
        !details.parameters.every(p=>p&&typeof p.name==='string'&&Number.isSafeInteger(p.index)&&(!p.expression||typeof p.expression==='string')))return null;
    const lines=[];
    const append=(text,style)=>{
      const compact=text.replace(/\s+/g,' ').trim();
      const chunks=compact.match(/.{1,56}(?:\s|$)|.{1,56}/gu)||[''];
      for(const chunk of chunks)lines.push({text:chunk.trim(),style});
    };
    append(node.name,'formula');
    for(const parameter of details.parameters){
      append('arg'+parameter.index+' · '+parameter.name,'caption');
      if(parameter.expression)append(parameter.expression,'expression');
    }
    const location=details.location?(details.ifCondition?'If condition':'Call site')+' · '+details.location:'No matching call site';
    append(details.sourceIssue?'Call site unavailable':location,'caption');
    if(lines.length>14)lines.splice(13,lines.length-13,{text:'See full details in the inspector',style:'caption'});
    return lines;
  }
  function traceOrder(document){
    const meta=document.metadata?.providerMetadata;
    if(meta?.formalKind!=='counterexample'||meta.hasMorePages||meta.pageComplete===false||meta.selectionComplete===false||meta.frontierCount>0)return [];
    const ids=new Set(document.nodes.map(n=>n.id)),next=new Map(),incoming=new Set();
    if(ids.size<2)return [];
    for(const edge of document.edges){
      if(edge.role==='loopBack')continue;
      if(edge.role!=='observedTransition'||!ids.has(edge.source)||!ids.has(edge.target)||next.has(edge.source)||incoming.has(edge.target))return [];
      next.set(edge.source,edge.target);incoming.add(edge.target);
    }
    const roots=[...ids].filter(id=>!incoming.has(id));
    if(roots.length!==1)return [];
    const steps=[];
    for(let id=roots[0];id!==undefined;id=next.get(id))steps.push(id);
    return steps.length===ids.size?steps:[];
  }
  const proofFont='-apple-system, BlinkMacSystemFont, Helvetica Neue, sans-serif';
  const proofWidth=264;
  const checkOutcomes=new Map([['passed',{label:'✓ Passed',tone:'positive',priority:0}],
    ['notVerified',{label:'? Not verified',tone:'neutral',priority:1}],
    ['failed',{label:'× Failed',tone:'negative',priority:2}]]);
  function specificationReport(document,byID=new Map(document.nodes.map(n=>[n.id,n]))){
    if(document.metadata?.verificationReport!==undefined)return projectReport(document,byID);
    const report=document.metadata?.specVerification;
    if(report===undefined)return null;
    const incomplete={summary:{title:'Incomplete verification report',tone:'neutral',symbol:'?',open:[]},marks:new Map()};
    if(!Array.isArray(report?.checks)||!report.checks.length||!Array.isArray(report.openQuestions))return incomplete;
    const open=new Set(report.openQuestions);
    if(open.size!==report.openQuestions.length||[...open].some(id=>!byID.has(id)))return incomplete;
    const ids=new Set(),marks=new Map();
    let passed=0,failed=0;
    for(const check of report.checks){
      const mark=checkOutcomes.get(check?.outcome);
      if(!mark||typeof check.id!=='string'||!check.id.trim()||ids.has(check.id)||
         !byID.has(check.nodeID)||!byID.has(check.evidenceID))return incomplete;
      ids.add(check.id);
      if(check.outcome==='passed')passed++;
      if(check.outcome==='failed')failed++;
      for(const id of [check.nodeID,check.evidenceID]){
        if(!marks.has(id)||mark.priority>marks.get(id).priority)marks.set(id,mark);
      }
    }
    const pending=ids.size-passed-failed;
    let title=passed+' of '+ids.size+' checks passed',tone='positive',symbol='✓';
    if(failed){title=failed+' of '+ids.size+' checks failed';tone='negative';symbol='×';}
    else if(pending){title=pending+' of '+ids.size+' checks not verified';tone='neutral';symbol='?';}
    return {summary:{title,tone,symbol,open:[...open].map(id=>byID.get(id).label)},marks};
  }

  function projectReport(document,byID){
    const report=document.metadata.verificationReport;
    const incomplete={summary:{title:'Invalid project verification report',tone:'neutral',symbol:'?',open:[],scope:'Complete acceptance inventory required'},marks:new Map()};
    const phases=['specification','implementation','correspondence'];
    const outcomes=new Set(['passed','failed','notVerified','unsupported','unknown']);
    if(![1,2].includes(report?.schemaVersion)||!Array.isArray(report.inventory)||!report.inventory.length||!Array.isArray(report.requirements)||!Array.isArray(report.evidence))return incomplete;
    let gatesPassed=true,returnTo=null;
    if(report.schemaVersion===2){
      const workflow=report.workflow,order=['requirements',...phases,'integration'];
      if(workflow?.schemaVersion!==1||!Array.isArray(workflow.stages)||workflow.stages.length!==order.length||!['passed','failed','incomplete'].includes(workflow.outcome))return incomplete;
      let blocked=false;
      for(const [index,stage]of workflow.stages.entries()){
        if(stage.id!==order[index]||!byID.has(stage.nodeID)||!['passed','failed','incomplete','blocked'].includes(stage.status)||!['passed','incomplete'].includes(stage.review))return incomplete;
        if(stage.status==='passed'&&(blocked||stage.evidence!=='passed'||stage.review!=='passed'))return incomplete;
        if(stage.status!=='passed')blocked=true;
      }
      gatesPassed=!blocked;returnTo=workflow.returnTo;
      if(gatesPassed!==(workflow.outcome==='passed')||workflow.outcome!==report.outcome||(gatesPassed?returnTo!==null:!order.includes(returnTo)))return incomplete;
    }
    const expected=new Set(report.inventory),seen=new Set(),marks=new Map(),counts=Object.fromEntries(phases.map(p=>[p,0]));
    if(report.inventory.some(id=>typeof id!=='string'||!id.trim())||report.evidence.some(claim=>!claim||typeof claim.id!=='string'||!claim.id.trim()))return incomplete;
    const evidence=new Map(report.evidence.map(claim=>[claim.id,claim]));
    if(evidence.size!==report.evidence.length)return incomplete;
    if(expected.size!==report.inventory.length||report.requirements.length!==expected.size)return incomplete;
    let passed=0,failed=0;
    for(const requirement of report.requirements){
      if(typeof requirement?.id!=='string'||!expected.has(requirement.id)||seen.has(requirement.id)||!byID.has(requirement.nodeID))return incomplete;
      seen.add(requirement.id);
      let complete=true,negative=false;
      for(const phase of phases){
        const assessment=requirement[phase];
        if(!assessment||!outcomes.has(assessment.outcome)||!Array.isArray(assessment.claims))return incomplete;
        for(const id of assessment.claims){
          const claim=evidence.get(id),prefix=phase==='specification'?'specification.':phase==='correspondence'?'translation.':null;
          if(!claim||!Array.isArray(claim.requirements)||!claim.requirements.includes(requirement.id)||typeof claim.domain!=='string')return incomplete;
          if(prefix?!claim.domain.startsWith(prefix):!['generatedModel.','source.'].some(p=>claim.domain.startsWith(p)))return incomplete;
          if(assessment.outcome==='passed'&&(claim.outcome!=='passed'||phase==='correspondence'&&claim.domain!=='translation.validated'))return incomplete;
        }
        if(assessment.outcome==='passed'){
          if(!assessment.claims.length)return incomplete;
          counts[phase]++;
        }else complete=false;
        if(assessment.outcome==='failed')negative=true;
      }
      if(complete)passed++;
      if(negative)failed++;
      marks.set(requirement.nodeID,checkOutcomes.get(negative?'failed':complete&&gatesPassed?'passed':'notVerified'));
    }
    if(report.schemaVersion===2){
      if((report.outcome==='failed')!==(failed>0)||report.outcome==='passed'&&passed!==expected.size)return incomplete;
      for(const stage of report.workflow.stages)marks.set(stage.nodeID,checkOutcomes.get(stage.status==='passed'?'passed':stage.status==='failed'?'failed':'notVerified'));
      if(!gatesPassed)passed=0;
    }
    const title=failed?'Project verification failed · '+failed+' requirements':
      passed===expected.size?'All '+passed+' project requirements verified':'Project verification incomplete · '+passed+' of '+expected.size+' requirements verified';
    const scope='Specification '+counts.specification+'/'+expected.size+' · Code '+counts.implementation+'/'+expected.size+' · Correspondence '+counts.correspondence+'/'+expected.size+(returnTo?' · Return to '+returnTo:'');
    return {summary:{title,tone:failed?'negative':passed===expected.size?'positive':'neutral',symbol:failed?'×':passed===expected.size?'✓':'?',open:[],scope},marks};
  }

  // The worker lays out the same measured rows as the renderer.
  function proofCardLayout(node,context,mark){
    const rows=[];
    let y=12;
    function paragraph(value,x,font,weight,leading,ink){
      if(!value)return;
      if(context)context.font=weight+' '+font+'px '+proofFont;
      // DOM-free projections use a conservative em per character.
      const width=text=>context?context.measureText(text).width:Array.from(text).length*font;
      const available=proofWidth-x-16;
      const emit=text=>{rows.push({text,x,y:y+font,font,weight,ink});y+=leading;};
      let line='';
      for(const word of String(value).trim().split(/\s+/u)){
        const candidate=line?line+' '+word:word;
        if(width(candidate)<=available){line=candidate;continue;}
        if(line)emit(line);
        line=word;
        if(width(word)>available){
          line='';
          for(const glyph of word){
            if(line&&width(line+glyph)>available){emit(line);line='';}
            line+=glyph;
          }
        }
      }
      if(line)emit(line);
    }
    paragraph(mark?mark.label+' · '+node.role:node.role,30,13,600,18,'accent');
    y+=4;
    paragraph(node.label,16,19,600,25,'text');
    const status=node.details?.reportedStatus||node.details?.status;
    if(typeof status==='string'&&status&&status!==node.role){
      y+=4;
      paragraph(status,16,13,400,18,'secondary');
    }
    return {rows,width:proofWidth,height:y+12,tone:mark?.tone};
  }

  function proofCard(node,palette){
    const {width,height,rows}=node.proofCard;
    const colors={...palette,accent:palette.accent||palette.secondary};
    const text=rows.map(row=>`<text x="${row.x}" y="${row.y}" font-size="${row.font}" font-weight="${row.weight}" fill="${colors[row.ink]}">${escape(row.text)}</text>`).join('');
    return 'data:image/svg+xml;utf8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" font-family="${proofFont}"><title>${escape(node.name)}</title><circle cx="19" cy="20" r="3" fill="${colors.accent}"/>${text}</svg>`);
  }
  function size(node){
    if(node.proofCard)return {width:node.proofCard.width,height:node.proofCard.height};
    if(node.canvas?.svg){const match=node.canvas.svg.match(/viewBox\s*=\s*["']\s*[\d.-]+[ ,]+[\d.-]+[ ,]+([\d.]+)[ ,]+([\d.]+)/);const ratio=match?Number(match[2])/Number(match[1]):.65;return {width:960,height:Math.max(64,Math.min(10000,960*ratio))};}
    const lines=conditionLines(node);
    if(lines)return {width:Math.min(580,Math.max(268,Math.max(...lines.map(l=>l.text.length))*10+30)),height:42+lines.length*23};
    if(node.canvas?.details?.attributes?.isDeclaredRoot&&node.canvas.role==='Verification condition'||['Entry point','Precondition','Postcondition','Expected termination'].includes(node.canvas?.role))return {width:Math.min(420,Math.max(200,node.name.length*13+30)),height:84};
    if(node.canvas?.role==='note')return {width:240,height:88};
    if(node.kind==='canvasEvent')return {width:22,height:22};
    if(['initial','final','pseudostate'].includes(node.canvas?.role))return {width:28,height:28};
    if(node.kind==='canvasLane')return {width:264,height:88};
    if(node.canvas?.role==='condition')return {width:160,height:88};
    return {width:264,height:88};
  }
  const fileLanguages=new Map(Object.entries({
    swift:'swift',rs:'rust',ts:'typescript',tsx:'typescript',mts:'typescript',cts:'typescript',
    js:'javascript',jsx:'javascript',cjs:'javascript',mjs:'javascript',py:'python',go:'go',
    kt:'kotlin',java:'java',c:'c',cpp:'cplusplus',hpp:'cplusplus',tf:'terraform',lean:'lean',tla:'tla',sql:'sql'
  }));
  // Language evidence is independent of the node label and human-readable status.
  function nodeLanguage(node){
    const explicit=node.language??node.details?.language;
    if(typeof explicit==='string'&&explicit.trim())return explicit;
    const path=(Array.isArray(node.sourcePath)?node.sourcePath.at(-1):null)||node.source?.path;
    if(typeof path==='string'){
      const extension=path.match(/\.([^.\/]+)$/)?.[1].toLowerCase();
      if(fileLanguages.has(extension))return fileLanguages.get(extension);
    }
    if(!Array.isArray(node.details?.checkouts))return 'none';
    const evidence=Array.isArray(node.details.evidence)?node.details.evidence:[];
    const languages=new Set();
    for(const item of [node.details.manifest,...evidence]){
      if(typeof item!=='string')continue;
      const name=item.split('/').pop();
      if(name==='tsconfig.json')languages.add('typescript');
      if(name==='Cargo.toml')languages.add('rust');
      if(name==='Package.swift')languages.add('swift');
      if(name.endsWith('.tf'))languages.add('terraform');
    }
    return languages.size===1?[...languages][0]:'none';
  }
  function view(session){
    const document=session.document,state=session.state||{},collapsed=new Set(state.collapsed||[]),parents=new Map(document.nodes.map(n=>[n.id,n.parentID])),byID=new Map(document.nodes.map(n=>[n.id,n]));
    const visible=new Set(),filter=state.filter||{},text=(filter.text||'').toLowerCase(),roles=new Set(filter.roles||[]);
    const ancestor=(id,visit)=>{const seen=new Set();let parent=parents.get(id);while(parent&&!seen.has(parent)){seen.add(parent);if(visit(parent)===false)return false;parent=parents.get(parent);}return true;};
    for(const node of document.nodes){if(!ancestor(node.id,id=>!collapsed.has(id)))continue;if(text&&!node.label.toLowerCase().includes(text)||roles.size&&!roles.has(node.role))continue;visible.add(node.id);ancestor(node.id,id=>{visible.add(id);});}
    const ir=document.metadata?.architectureIR,originals=new Map((ir?.nodes||ir?.entities||[]).map(n=>[n.id,n]));
    const report=specificationReport(document,byID);
    const groups=new Set(document.nodes.filter(n=>visible.has(n.id)&&visible.has(n.parentID)).map(n=>n.parentID));
    const nodes=document.nodes.filter(n=>visible.has(n.id)).map(n=>originals.has(n.id)?{...originals.get(n.id),canvasOrigin:{...n,diagram:document.kind,source:{...(n.source||{}),entityID:n.id,snapshotID:ir.snapshotID||ir.id}}}:{id:n.id,name:n.label,kind:groups.has(n.id)?'canvasGroup':document.kind==='sequence'?'canvasEvent':'canvas',language:nodeLanguage(n),attributes:{},canvas:{...n,diagram:document.kind}});
    if(document.kind==='proofDependencies'){
      const context=scope.document?.createElement('canvas').getContext('2d');
      for(const node of nodes){
        if(node.kind==='canvas'&&node.canvas)node.proofCard=proofCardLayout(node.canvas,context,report?.marks.get(node.id));
      }
    }
    const edges=[],edgeIDs=new Set();
    const endpoint=id=>{let current=id;ancestor(id,parent=>{if(collapsed.has(parent))current=parent;});return visible.has(current)?current:null;};
    for(const edge of document.edges){const source=endpoint(edge.source),target=endpoint(edge.target);if(!source||!target||source===target&&edge.source!==edge.target)continue;edges.push({...edge,source,target,kind:edge.role||'relation',canvas:edge});edgeIDs.add(edge.id);}
    for(const node of nodes)if((node.canvas||node.canvasOrigin).parentID&&visible.has((node.canvas||node.canvasOrigin).parentID)&&!edges.some(edge=>edge.kind==='contains'&&edge.source===(node.canvas||node.canvasOrigin).parentID&&edge.target===node.id)){let id='__contains:'+node.id;while(edgeIDs.has(id))id+=':';edges.push({id,source:(node.canvas||node.canvasOrigin).parentID,target:node.id,kind:'contains',canvas:{label:'Contains',role:'contains',directed:true}});}
    if(document.kind==='sequence')for(const lane of document.lanes){const id='__lane:'+lane.id;{nodes.push({id,name:lane.label,kind:'canvasLane',language:'none',attributes:{},canvas:{role:'lane',diagram:'sequence'}});for(const node of nodes.filter(n=>n.canvas.laneID===lane.id))edges.push({id:'__lane-contains:'+node.id,source:id,target:node.id,kind:'contains',canvas:{label:'Lane',role:'contains',directed:true}});}}
    if(document.kind==='sequence')for(const [index,fragment]of (document.metadata?.fragments||[]).entries())nodes.push({id:'__fragment:'+index,name:[fragment.kind,fragment.label].filter(Boolean).join(' · '),kind:'canvasFragment',language:'none',attributes:{},canvas:{role:'fragment',details:fragment,diagram:'sequence'}});
    if(document.svg)nodes.push({id:'__svg',name:document.title,kind:'canvas',language:'none',attributes:{},canvas:{role:'image',svg:document.svg,diagram:document.kind}});
    const origin=ir||document.metadata?.origin||{};
    return {workspaceID:'canvas:'+session.viewSessionID,snapshotID:document.sourceDigest,queryID:session.viewSessionID,nodes,edges,evidence:origin.evidence||[],coverage:origin.coverage||[],freshness:origin.freshness||document.metadata?.applicability||'imported',completeness:origin.completeness||(origin.truncated?'partial':'completeWithinScope'),truncated:!!origin.truncated,canvas:{specReport:report?.summary||null,verification:verificationSummary(document),sourceIR:!!ir,kind:document.kind,layout:state.layout||'auto',metadata:document.metadata||{},title:document.title,format:document.format,totalNodes:document.nodes.length,totalEdges:document.edges.length},diagnostics:[]};
  }
  function sequenceLayout(request){
    const lanes=request.nodes.filter(n=>n.kind==='canvasLane'),events=request.nodes.filter(n=>n.kind==='canvasEvent'),orders=[...new Set(events.map(n=>n.canvas.order))].sort((a,b)=>a-b),nodes=[],routes=[],rows=new Map();let y=120;
    for(const order of orders){let slots=1;for(const lane of lanes)slots=Math.max(slots,events.filter(n=>'__lane:'+n.canvas.laneID===lane.id&&n.canvas.order===order).length);const rowEvents=events.filter(n=>n.canvas.order===order),note=rowEvents.some(n=>n.canvas.role==='note');const height=Math.max(72,slots*32+40,note?128:0);rows.set(order,{y,height});y+=height;}
    const height=Math.max(184,y-28);
    lanes.forEach((lane,i)=>{const members=events.filter(n=>'__lane:'+n.canvas.laneID===lane.id);nodes.push({id:lane.id,x:28+i*320,y:28,width:264,height:members.length?height:88,group:!!members.length});for(const order of orders){const matching=members.filter(n=>n.canvas.order===order);matching.forEach((event,slot)=>{const bounds=size(event);nodes.push({id:event.id,x:28+i*320+(264-bounds.width)/2,y:rows.get(order).y+slot*32,...bounds,group:false});});}});
    const byID=new Map(nodes.map(n=>[n.id,n]));
    for(const edge of request.edges){const a=byID.get(edge.source),b=byID.get(edge.target);if(a&&!a.group&&b&&!b.group&&a.x===b.x&&a.id!==b.id){routes.push({id:edge.id,points:[{x:a.x+22,y:a.y+11},{x:a.x+100,y:a.y+11},{x:b.x+100,y:b.y+11},{x:b.x+22,y:b.y+11}]});}}
    for(const fragment of request.nodes.filter(n=>n.kind==='canvasFragment')){const data=fragment.canvas.details,start=orders.find(order=>order>=data.start),end=orders.filter(order=>order<data.end).at(-1);const top=start===undefined?120:rows.get(start).y-16,bottom=end===undefined?top+40:rows.get(end).y+rows.get(end).height-20;nodes.push({id:fragment.id,x:16,y:top,width:Math.max(264,lanes.length*320-32),height:Math.max(40,bottom-top),group:false});}
    return {generation:request.generation,queryID:request.queryID,snapshotID:request.snapshotID,nodes,routes};
  }
  function card(node,width,height,group,palette,fit,marks){
    if(node.proofCard&&!group)return proofCard(node,palette);
    if(node.canvas.svg)return 'data:image/svg+xml;utf8,'+encodeURIComponent(node.canvas.svg);
    const titleSize=21;
    if(node.kind==='canvasLane')return 'data:image/svg+xml;utf8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect x="1" y="1" width="${width-2}" height="62" rx="5" fill="${palette.header}" stroke="${palette.divider}"/><text x="${width/2}" y="36" text-anchor="middle" font-size="${titleSize}" font-weight="600" font-family="-apple-system, sans-serif" fill="${palette.text}">${escape(fit(node.name,width-24,titleSize,600))}</text><path d="M${width/2} 64V${height}" stroke="${palette.secondary}" stroke-dasharray="5 5"/></svg>`);
    const {role}=node.canvas;
    if(node.kind==='canvasEvent'&&role!=='note'||['initial','final','pseudostate'].includes(role))return 'data:image/svg+xml;utf8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><circle cx="${width/2}" cy="${height/2}" r="${Math.min(width,height)/2-3}" fill="${role==='final'?'none':palette.text}" stroke="${palette.text}"/>${role==='final'?`<circle cx="${width/2}" cy="${height/2}" r="${Math.min(width,height)/2-7}" fill="${palette.text}"/>`:''}</svg>`);
    const lines=conditionLines(node);
    if(lines){
      const rows=lines.map(({text,style},i)=>{
        const caption=style==='caption',font=caption?13:16;
        return `<text x="12" y="${50+i*23}" font-family="${caption?'-apple-system, sans-serif':'monospace'}" font-size="${font}" fill="${caption?palette.secondary:palette.text}">${escape(fit(text,width-24,font,400))}</text>`;
      }).join('');
      return 'data:image/svg+xml;utf8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><path d="M0 0H${width}V26H0Z" fill="${palette.header}"/><text x="12" y="18" font-size="12" font-family="-apple-system,sans-serif" fill="${palette.secondary}">${escape(role)}</text>${rows}</svg>`);
    }
    const title=fit(node.name,width-24,titleSize,600),labelX=marks?.language?62:marks?38:12;
    const label=fit(role,width-labelX-12,10,400);
    const status=node.canvas.details?.reportedStatus||node.canvas.details?.status||(node.name!==node.id?node.id:'');
    return 'data:image/svg+xml;utf8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${group?64:height}"><title>${escape(node.name)}</title><path d="M0 0H${width}V26H0Z" fill="${palette.header}"/><path d="M0 26H${width}" stroke="${palette.divider}"/>${marks?.role||''}${marks?.language||''}<text x="${labelX}" y="18" font-size="10" font-family="-apple-system, sans-serif" fill="${palette.secondary}">${escape(label)}</text><text x="12" y="48" font-size="${titleSize}" font-weight="600" font-family="-apple-system, sans-serif" fill="${palette.text}">${escape(title)}</text>${!group&&status?`<text x="12" y="72" font-size="11" font-family="-apple-system, sans-serif" fill="${palette.secondary}">${escape(fit(status,width-24,11,400))}</text>`:''}</svg>`);
  }
  const api={kinds,specificationReport,formalModel,verificationSummary,conditionBackend,conditionVerdict,conditionGraphs,readConditionCall,traceOrder,size,view,sequenceLayout,card};if(typeof module!=='undefined'&&module.exports)module.exports=api;else scope.ArchitectureCanvasModel=api;
})(globalThis);
