/* Shared presentation model; recorded graph facts remain immutable. */
(function(scope){
  'use strict';
  const card=Object.freeze({width:264,height:112});
  const member=Object.freeze({width:640,height:32});
  const callable=Object.freeze({width:card.width,height:140});
  const isCallable=node=>['function','method'].includes(node.kind);
  const isProperty=node=>['property','field'].includes(node.kind)&&!['typeAlias','associatedType'].includes(node.attributes?.['declaration.kind']);
  const size=(node,group=false,cfg=false)=>group?card:node.canvas?scope.ArchitectureCanvasModel.size(node):isProperty(node)?member:isCallable(node)&&!cfg?callable:card;
  const frame=Object.freeze({padding:24,headerHeight:64,clearance:4});
  const headerHeight=(node,cfg=false)=>isCallable(node)&&!cfg?callable.height:frame.headerHeight;
  const inset=frame.padding+frame.clearance;
  const containers=new Set(['workspace','system','package','module','file','type','interface','actor','function','method','property','field','designGroup','canvasGroup','canvasLane']);
  const compare=(a,b)=>a.id<b.id?-1:a.id>b.id?1:0;
  function plan(request){
    const nodes=[...request.nodes].sort(compare),edges=[...request.edges].sort(compare);
    if(nodes.length>(request.canvas?756:500)||edges.length>(request.canvas?2500:1500))throw Error('Layout budget exceeded.');
    const byID=new Map(nodes.map(n=>[n.id,n]));
    if(byID.size!==nodes.length)throw Error('Duplicate layout entity identity.');
    for(const edge of edges)if(!byID.has(edge.source)||!byID.has(edge.target))throw Error('Layout edge endpoint is missing.');
    const cfg=(!request.canvas||request.canvas.sourceIR)&&(edges.some(e=>e.kind==='controlFlow')||nodes.some(n=>n.kind==='basicBlock'));
    const candidates=new Map(),owners=new Map(),parents=new Map();
    for(const edge of edges)if(edge.kind==='contains'&&edge.source!==edge.target){
      if(!candidates.has(edge.target))candidates.set(edge.target,new Set());
      candidates.get(edge.target).add(edge.source);
    }
    for(const [id,values]of candidates)if(values.size===1){const owner=[...values][0];owners.set(id,owner);if(!cfg&&containers.has(byID.get(owner).kind))parents.set(id,owner);}
    for(const id of byID.keys()){
      const visited=new Set([id]);let parent=parents.get(id);
      while(parent){if(visited.has(parent))throw Error('Cyclic containment cannot be displayed as frames.');visited.add(parent);parent=parents.get(parent);}
    }
    const groups=new Set(parents.values()),rows=new Set(nodes.filter(n=>isProperty(n)&&!groups.has(n.id)).map(n=>n.id));
    const memberCompare=(a,b)=>(byID.get(a.id).anchor?.startByte??Number.MAX_SAFE_INTEGER)-(byID.get(b.id).anchor?.startByte??Number.MAX_SAFE_INTEGER)||compare({id:byID.get(a.id).name||a.id},{id:byID.get(b.id).name||b.id})||compare(a,b);
    const hidden=new Set(edges.filter(e=>e.kind==='contains'&&(parents.get(e.target)===e.source||(cfg&&owners.get(e.target)===e.source&&['function','method'].includes(byID.get(e.source).kind)&&byID.get(e.target).kind==='basicBlock'))).map(e=>e.id));
    const direction=request.direction||{LR:'RIGHT',RL:'LEFT',TB:'DOWN',TD:'DOWN',BT:'UP'}[request.canvas?.metadata?.rankdir]||(['dataFlow','proofDependencies'].includes(request.canvas?.kind)?'RIGHT':'DOWN');
    const options={'elk.algorithm':'layered','elk.hierarchyHandling':'INCLUDE_CHILDREN','elk.direction':direction,'elk.edgeRouting':'ORTHOGONAL','elk.randomSeed':'1','elk.spacing.nodeNode':'36','elk.layered.spacing.nodeNodeBetweenLayers':'72','elk.layered.nodePlacement.strategy':'LINEAR_SEGMENTS','elk.layered.layering.strategy':'NETWORK_SIMPLEX','elk.padding':`[top=${inset+frame.headerHeight},left=${inset},bottom=${inset},right=${inset}]`};
    const boxes=new Map(nodes.map(n=>[n.id,groups.has(n.id)?{id:n.id,children:[],layoutOptions:{...options,'elk.padding':`[top=${inset+headerHeight(n,cfg)},left=${inset},bottom=${inset},right=${inset}]`,'elk.nodeSize.constraints':'MINIMUM_SIZE','elk.nodeSize.minimum':isCallable(n)?`(${callable.width},${callable.height})`:'(0,0)'}}:{id:n.id,...size(n,false,cfg)}]));
    const children=[];
    for(const node of nodes)(parents.has(node.id)?boxes.get(parents.get(node.id)).children:children).push(boxes.get(node.id));
    const ordered=edges.filter(e=>!hidden.has(e.id)&&(!cfg||e.kind==='controlFlow'));
    const graph={id:'__architecture_layout_root__',layoutOptions:{...options,'elk.padding':`[top=${inset},left=${inset},bottom=${inset},right=${inset}]`},children,edges:ordered.map(e=>({id:e.id,sources:[e.source],targets:[e.target]}))};
    // Function declarations are metadata headers, not executable control-flow blocks.
    const headers=cfg?nodes.filter(n=>n.kind==='function'||n.kind==='method').map(n=>n.id):[];
    if(headers.length)graph.children=children.filter(n=>!headers.includes(n.id));
    graph.edges=graph.edges.filter(e=>!headers.includes(e.sources[0])&&!headers.includes(e.targets[0]));
    const key=JSON.stringify([request.direction,request.canvas?.kind,request.canvas?.layout,request.canvas?.metadata?.rankdir,nodes.map(n=>[n.id,n.canvas?.order,n.canvas?.laneID]),nodes.map(n=>[n.id,n.kind,parents.get(n.id),size(n,groups.has(n.id),cfg)]),nodes.filter(n=>rows.has(n.id)).sort(memberCompare).map(n=>n.id),edges.map(e=>[e.id,e.source,e.target,e.kind,e.attributes?.['cfg.branch']])]);
    return {graph,parents,owners,groups,hidden,key,headers,cfg,rows,memberCompare};
  }
  async function layout(request,engine){
    if(request.canvas?.kind==='sequence')return scope.ArchitectureCanvasModel.sequenceLayout(request);
    const model=plan(request),localEdges=new Map();
    let crossesBoundary=false;
    for(const edge of model.graph.edges){
      const source=edge.sources[0],target=edge.targets[0],owner=model.parents.get(source)||model.graph.id;
      if(owner!==(model.parents.get(target)||model.graph.id))crossesBoundary=true;
      if(!localEdges.has(owner))localEdges.set(owner,[]);localEdges.get(owner).push(edge);
    }
    async function siblings(box,children,edges,padding){
      if(!edges.length||request.canvas?.layout==='grid'){
        children.sort((a,b)=>(b.children?b.width*b.height:0)-(a.children?a.width*a.height:0)||compare(a,b));
        const framed=children.some(n=>n.children),totalWidth=children.reduce((sum,n)=>sum+n.width,0),totalHeight=children.reduce((sum,n)=>sum+n.height,0);
        const columns=request.direction==='RIGHT'?Math.max(1,children.length):request.direction==='DOWN'||framed||!children.length?1:Math.max(1,Math.ceil(Math.sqrt(children.length*.85*totalHeight/totalWidth)));
        let y=padding,width=card.width;
        for(let i=0;i<children.length;i+=columns){const row=children.slice(i,i+columns);let x=inset,height=0;for(const child of row){child.x=x;child.y=y;x+=child.width+36;height=Math.max(height,child.height);}width=Math.max(width,x-36);y+=height+48;}
        return {...box,children,edges:[],width:width+inset,height:Math.max(padding+inset,y-48+inset)};
      }
      const result=await engine.layout({...box,children:children.map(n=>({id:n.id,width:n.width,height:n.height})),edges,layoutOptions:{...model.graph.layoutOptions,'elk.hierarchyHandling':'SEPARATE_CHILDREN','elk.padding':`[top=${padding},left=${inset},bottom=${inset},right=${inset}]`}});
      return {...result,children:result.children.map(position=>({...children.find(n=>n.id===position.id),x:position.x,y:position.y}))};
    }
    // At most 500 squared entries; avoid rewalking ancestry for every edge/scope.
    const immediate=new Map();
    if(model.rows.size)for(const node of request.nodes){
      let child=node.id,owner=model.parents.get(child)||model.graph.id;
      while(true){if(!immediate.has(owner))immediate.set(owner,new Map());immediate.get(owner).set(node.id,child);if(owner===model.graph.id)break;child=owner;owner=model.parents.get(child)||model.graph.id;}
    }
    const immediateChild=(id,owner)=>immediate.get(owner)?.get(id);
    async function solve(box){
      if(!box.children)return box;
      const children=[];for(const child of box.children)children.push(await solve(child));
      const padding=box.id===model.graph.id?inset:inset+headerHeight(request.nodes.find(n=>n.id===box.id)||{},model.cfg);
      if(!model.rows.size){const result=await siblings(box,children,localEdges.get(box.id)||[],padding);return {...result,width:Math.max(result.width,isCallable(request.nodes.find(n=>n.id===box.id)||{})?callable.width:0)};}
      const rows=children.filter(n=>model.rows.has(n.id)).sort(model.memberCompare),regular=children.filter(n=>!model.rows.has(n.id)),regularIDs=new Set(regular.map(n=>n.id));
      const edges=model.graph.edges.flatMap(edge=>{
        const source=immediateChild(edge.sources[0],box.id),target=immediateChild(edge.targets[0],box.id);
        return source&&target&&source!==target&&regularIDs.has(source)&&regularIDs.has(target)?[{...edge,sources:[source],targets:[target]}]:[];
      });
      const result=await siblings(box,regular,edges,padding+rows.length*member.height+(rows.length&&regular.length?24:0));
      rows.forEach((row,i)=>{row.x=inset;row.y=padding+i*member.height;});
      return {...result,children:[...rows,...result.children],width:Math.max(result.width,rows.length?member.width+2*inset:0,isCallable(request.nodes.find(n=>n.id===box.id)||{})?callable.width:0)};
    }
    // Cross-boundary relations need ELK's joint compound calculation. Independent
    // scopes can be composed bottom-up without letting containment distort ranks.
    const result=crossesBoundary&&!model.rows.size?await engine.layout(model.graph):await solve(model.graph),nodes=[],routes=[],offsets=new Map();
    const cfgHeaderOffset=model.headers.length?card.height+72:0;
    function visit(box,x=0,y=cfgHeaderOffset){
      const left=x+(box.x||0),top=y+(box.y||0);offsets.set(box.id,{x:left,y:top});
      if(box.id!==result.id)nodes.push({id:box.id,x:left,y:top,width:box.width,height:box.height,group:model.groups.has(box.id)});
      for(const child of box.children||[])visit(child,left,top);
    }
    visit(result);
    for(let i=0;i<model.headers.length;i++)nodes.push({id:model.headers[i],x:24+i*(card.width+36),y:24,...card});
    const directRoutes=new Set(model.graph.edges.filter(e=>!model.rows.has(e.sources[0])&&!model.rows.has(e.targets[0])&&!model.groups.has(e.sources[0])&&!model.groups.has(e.targets[0])&&(model.parents.get(e.sources[0])||model.graph.id)===(model.parents.get(e.targets[0])||model.graph.id)).map(e=>e.id));
    function collect(box){
      for(const edge of box.edges||[]){
        if(model.rows.size&&!directRoutes.has(edge.id))continue;
        // Simple recorded edges normally have one section. Compound boundary chains
        // retain native curves rather than misinterpreting section-local coordinates.
        if(edge.sections?.length!==1)continue;
        const section=edge.sections[0],offset=offsets.get(edge.container||box.id)||{x:0,y:cfgHeaderOffset};
        const points=[section.startPoint,...(section.bendPoints||[]),section.endPoint].map(p=>({x:p.x+offset.x,y:p.y+offset.y}));
        if(points.every(p=>Number.isFinite(p.x)&&Number.isFinite(p.y)))routes.push({id:edge.id,points});
      }
      for(const child of box.children||[])collect(child);
    }
    collect(result);
    return {generation:request.generation,queryID:request.queryID,snapshotID:request.snapshotID,nodes,routes};
  }
  const api={card,member,callable,isCallable,isProperty,size,frame,headerHeight,plan,layout};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;else scope.ArchitectureLayout=api;
})(globalThis);
