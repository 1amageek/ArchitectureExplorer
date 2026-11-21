// Integer coordinates are shared by every area, object port, grid line and path.
globalThis.C4Layout = (() => {
  // Scale the mesh, its hit target and the grid clearance together.
  const objectScale = 2.75;
  const portRadius = Math.ceil(objectScale);
  const clearance = portRadius - 1;

  function plan(nodes, edges, subject) {
    const areas = new Map(), objects = new Map(), roots = [];
    function area(id, name, siblings) {
      if (!areas.has(id)) {
        const entry = {id, name, children: []};
        areas.set(id, entry);
        siblings.push(entry);
      }
      return areas.get(id);
    }
    const sorted = [...nodes].sort((a,b) => a.id.localeCompare(b.id));
    const owner = nodes.find(n => n.id === subject);
    function domain(node) {
      let siblings = roots;
      for (const item of node?.attributes?.['context.areas'] || []) {
        siblings = area(item.id, item.name, siblings).children;
      }
      return siblings;
    }
    for (const node of sorted.filter(n=>!n.attributes?.['context.owner'])) {
      if (owner && node.id === owner.id) area(node.id,node.name,domain(node));
      else domain(node).push({id:node.id,name:node.name,node});
    }
    for (const node of sorted.filter(n=>n.attributes?.['context.owner'])) {
      const parent=areas.get(node.attributes['context.owner']);
      (parent?.children || domain(node)).push({id:node.id,name:node.name,node});
    }
    const root={children:roots};
    // At each boundary a relationship connects two direct children, or leads
    // outside that boundary. Keep this projection separate from the model edge.
    const ancestry=new Map(), links=new Map();
    function index(item, parents){
      if(item.id)ancestry.set(item.id,parents);
      for(const child of item.children||[])index(child,new Map(parents).set(item,child));
    }
    index(root,new Map());
    for(const edge of edges){
      const from=ancestry.get(edge.source),to=ancestry.get(edge.target);
      if(!from||!to)continue;
      for(const parent of new Set([...from.keys(),...to.keys()])){
        const source=from.get(parent),target=to.get(parent);
        if(source===target)continue;
        if(!links.has(parent))links.set(parent,[]);
        links.get(parent).push([source,target,edge]);
      }
    }
    function measure(item) {
      if (!item.children?.length) {
        const count=Math.min(500,item.node?.attributes?.['context.containerCount']||0);
        const columns=Math.ceil(Math.sqrt(count));
        item.width=count ? 2+columns*10 : 8;
        item.depth=count ? 2+Math.ceil(count/columns)*10 : 8;
        return;
      }
      for (const child of item.children) measure(child);
      const columns = Math.ceil(Math.sqrt(item.children.length));
      const children=item.children, flow=links.get(item)||[];
      const slots=children.map((_,i)=>({x:i%columns,z:Math.floor(i/columns)}));
      // Projected horizontal direction on the isometric floor is x - z.
      const across=p=>p.x-p.z;
      const weight=new Map(children.map(child=>[child,0]));
      for(const [a,b] of flow){
        if(a)weight.set(a,weight.get(a)+(b?1:-1));
        if(b)weight.set(b,weight.get(b)+(a?-1:1));
      }
      const order=[...children].sort((a,b)=>weight.get(b)-weight.get(a)||a.id.localeCompare(b.id));
      const ranks=slots.map((_,i)=>i).sort((i,j)=>across(slots[i])-across(slots[j])||i-j);
      const assignment=[...children];
      if(flow.length)order.forEach((child,i)=>assignment[ranks[i]]=child);
      function geometry(arr){
        const widths=[],depths=[];
        arr.forEach((child,i)=>{
          const {x,z}=slots[i];
          widths[x]=Math.max(widths[x]||0,child.width);
          depths[z]=Math.max(depths[z]||0,child.depth);
        });
        const offsets=sizes=>{
          const out=[2];
          for(const size of sizes)out.push(out.at(-1)+size+2);
          return out;
        };
        return {x:offsets(widths),z:offsets(depths)};
      }
      // Include the real port inside a nested area when choosing its location.
      function localPort(child,id){
        if(!child)return null;
        let x=0,z=0;
        for(let next; (next=ancestry.get(id).get(child)); child=next){x+=next.dx;z+=next.dz;}
        return child.children?[x,z+2]:[x+child.width/2,z+child.depth/2];
      }
      const portPairs=flow.map(([a,b,e])=>[a,b,localPort(a,e.source),localPort(b,e.target)]);
      function cost(arr){
        const grid=geometry(arr),pos=new Map(arr.map((child,i)=>[child,[grid.x[slots[i].x],grid.z[slots[i].z]]]));
        let score=0;
        for(const [source,target,from,to] of portPairs){
          const a=pos.get(source),b=pos.get(target);
          if(a&&b){
            const dx=b[0]+to[0]-a[0]-from[0],dz=b[1]+to[1]-a[1]-from[1];
            score+=Math.abs(dx)+Math.abs(dz)+4*Math.max(0,dz-dx);
          }else if(a)score-=a[0]+from[0]-a[1]-from[1];
          else if(b)score+=b[0]+to[0]-b[1]-to[1];
        }
        return score;
      }
      // Refine small sibling sets locally, keeping larger diagrams bounded.
      if(flow.length && flow.length<=128 && children.length<=16){
        let best=cost(assignment);
        for(let pass=0;pass<2;pass++)for(let i=0;i<assignment.length;i++)for(let j=i+1;j<assignment.length;j++){
          [assignment[i],assignment[j]]=[assignment[j],assignment[i]];
          const next=cost(assignment);
          if(next<best)best=next;
          else [assignment[i],assignment[j]]=[assignment[j],assignment[i]];
        }
      }
      const {x,z}=geometry(assignment);
      assignment.forEach((child,i)=>{child.dx=x[slots[i].x];child.dz=z[slots[i].z];});
      item.width=x.at(-1);item.depth=z.at(-1);
    }
    function place(item,x,z) {
      item.x=x; item.z=z;
      if (item.children) {
        for (const child of item.children) place(child,x+child.dx,z+child.dz);
      } else objects.set(item.id,item);
    }
    measure(root); place(root,0,0);
    const positions=new Map();
    for (const item of objects.values()) positions.set(item.id,[item.x+item.width/2,item.z+item.depth/2]);
    for (const item of areas.values()) positions.set(item.id,[item.x,item.z+2]);
    const blocked=new Set();
    const key=(x,z)=>x+','+z;
    for (const item of objects.values()) {
      const [x,z]=positions.get(item.id);
      for(let i=-clearance;i<=clearance;i++) for(let j=-clearance;j<=clearance;j++) blocked.add(key(x+i,z+j));
    }
    const lanes=new Map(), paths=[];
    for(const edge of [...edges].sort((a,b)=>a.id.localeCompare(b.id))) {
      const a=positions.get(edge.source), b=positions.get(edge.target);
      if (!a||!b) continue;
      const options=[];
      const sourceObject=objects.has(edge.source),targetObject=objects.has(edge.target);
      // Preserve a visible straight segment before the target port, even when
      // the search falls back to walking the lattice.
      function offAxis(x,z,center,radius) {
        const dx=Math.abs(x-center[0]),dz=Math.abs(z-center[1]);
        return dx>0&&dz>0&&Math.max(dx,dz)<=radius;
      }
      function permitted(x,z) {
        if(sourceObject&&offAxis(x,z,a,clearance)||targetObject&&offAxis(x,z,b,portRadius))return false;
        return !blocked.has(key(x,z))||sourceObject&&Math.max(Math.abs(x-a[0]),Math.abs(z-a[1]))<=clearance||
          targetObject&&Math.max(Math.abs(x-b[0]),Math.abs(z-b[1]))<=clearance;
      }
      function candidate(points,direct=false,setback=0) {
        if(direct&&blocked.has(key(...points.at(-1))))return;
        const vertices=[points[0]];
        for(const point of points.slice(1)){
          const [x,z]=vertices.at(-1),dx=point[0]-x,dz=point[1]-z;
          if(dx&&dz)return;
          if(!dx&&!dz)continue;
          const previous=vertices.at(-2);
          if(previous&&(dx&&previous[1]===z||dz&&previous[0]===x)){
            if(dx*(x-previous[0])+dz*(z-previous[1])<0)return;
            vertices[vertices.length-1]=point;
          }else vertices.push(point);
        }
        if(vertices.length<2)return;
        const steps=[];
        let score=setback;
        for(let i=1;i<vertices.length;i++) {
          const [x,z]=vertices[i-1],[ex,ez]=vertices[i],dx=Math.sign(ex-x),dz=Math.sign(ez-z);
          const n=Math.abs(ex-x)+Math.abs(ez-z);
          const entry=!direct&&i===vertices.length-1&&targetObject?portRadius:0;
          if(n<=entry)return;
          for(let j=0;j<n;j++) {
            const px=x+dx*j,pz=z+dz*j;
            const insideSource=sourceObject&&Math.max(Math.abs(px-a[0]),Math.abs(pz-a[1]))<=clearance;
            if(direct?blocked.has(key(px,pz))&&!insideSource:!permitted(px,pz))return;
            if(j>=n-entry)continue;
            const step=key(px+dx/2,pz+dz/2);
            steps.push(step); score+=1+(lanes.get(step)||0)*4;
          }
          if(entry)vertices[i]=[ex-dx*entry,ez-dz*entry];
        }
        const target=vertices.at(-1), approach=vertices.at(-2);
        const behind=approach[0]+approach[1]<target[0]+target[1];
        score+=(vertices.length-2)*2+(behind?4:0);
        options.push({points:vertices,steps,score});
      }
      function directRoutes(){
        for(const axis of [0,1]){
          const cross=1-axis,direction=Math.sign(b[axis]-a[axis]);
          if(!direction)continue;
          const sourceSpan=sourceObject?clearance-1:0,targetSpan=targetObject?clearance:0;
          const low=Math.max(a[cross]-sourceSpan,b[cross]-targetSpan);
          const high=Math.min(a[cross]+sourceSpan,b[cross]+targetSpan);
          // Prefer the middle of the approach face, then spread shared lanes.
          for(const lane of Array.from({length:Math.max(0,high-low+1)},(_,i)=>low+i).sort((l,r)=>Math.abs(l-b[cross])-Math.abs(r-b[cross]))){
            const from=[...a],to=[...b];
            from[cross]=to[cross]=lane;
            // A rear diagonal moves toward the raised silhouette when both
            // coordinates are lower than its center. Keep its arrow clear.
            const setback=targetObject&&direction>0?Math.max(0,b[cross]-lane):0;
            if(targetObject)to[axis]-=(portRadius+setback)*direction;
            if(Math.sign(to[axis]-from[axis])===direction)candidate([from,to],true,setback);
          }
        }
      }
      if(a[0]===b[0]&&a[1]===b[1]) {
        const reach=portRadius+2;
        candidate([a,[a[0]+reach,a[1]],[a[0]+reach,a[1]+reach],[a[0],a[1]+reach],b]);
      } else {
        directRoutes();
        if(!options.length)for(const d of [0,-2,2,-3,3,-4,4]) {
          for(const x of [a[0]+d,b[0]+d])candidate([a,[x,a[1]],[x,b[1]],b]);
          for(const z of [a[1]+d,b[1]+d])candidate([a,[a[0],z],[b[0],z],b]);
        }
        // The one-cell corridors outside the two footprints are always open.
        if(!options.length) for(const d of [-3,3])for(const e of [-3,3]) {
          const ax=a[0]+d,bx=b[0]+e,lane=Math.min(a[1],b[1])-3;
          candidate([a,[ax,a[1]],[ax,lane],[bx,lane],[bx,b[1]],b]);
        }
      }
      options.sort((l,r)=>l.score-r.score||l.points.length-r.points.length);
      let route=options[0];
      if(!route) {
        // Search the free lattice when both simple elbows and the side corridors are obstructed.
        const queue=[a], parent=new Map([[key(...a),null]]);
        for(let cursor=0;cursor<queue.length&&!parent.has(key(...b));cursor++){
          const [x,z]=queue[cursor];
          for(const [dx,dz] of [[1,0],[0,1],[-1,0],[0,-1]]){
            const nx=x+dx,nz=z+dz,k=key(nx,nz);
            if(nx<0||nz<0||nx>root.width||nz>root.depth||parent.has(k))continue;
            if(!permitted(nx,nz))continue;
            parent.set(k,[x,z]);queue.push([nx,nz]);
          }
        }
        if(!parent.has(key(...b)))throw Error('No grid route for relation '+edge.id);
        const reversed=[];
        for(let p=b;p;p=parent.get(key(...p)))reversed.push(p);
        const points=reversed.reverse().filter((p,i,arr)=>!i||i===arr.length-1||
          (arr[i-1][0]!==arr[i+1][0]&&arr[i-1][1]!==arr[i+1][1]));
        candidate(points);
        route=options[0];
      }
      for(const s of route.steps)lanes.set(s,(lanes.get(s)||0)+1);
      paths.push({edge,points:route.points});
    }
    function visibleAreas(ids){
      const result=new Set();
      function visit(item){
        let included=ids.has(item.id);
        for(const child of item.children||[])if(visit(child))included=true;
        if(item.children&&included)result.add(item.id);
        return included;
      }
      for(const item of roots)visit(item);
      return result;
    }
    return {areas:[...areas.values()],objects:[...objects.values()],paths,positions,root,visibleAreas};
  }
  // Caption metrics are measured in CSS pixels. Anchors and results are map coordinates.
  function placeCaptions(items, footprints, scale, subject) {
    const occupied=footprints.map(box=>({box}));
    const gap=3/scale, placements=new Map();
    const segments=items.filter(item=>item.type==='edge-label').flatMap(item=>item.segments);
    function intersects(segment,box) {
      let start=0,end=1;
      for(const [axis,min,max] of [[0,box.left,box.right],[1,box.top,box.bottom]]){
        const origin=segment.a[axis],delta=segment.b[axis]-origin;
        if(!delta){if(origin<min||origin>max)return false;continue;}
        const a=(min-origin)/delta,b=(max-origin)/delta;
        start=Math.max(start,Math.min(a,b));end=Math.min(end,Math.max(a,b));
      }
      return start<=end;
    }
    for(const item of items){
      const height=item.height/scale;
      let fallback,chosen,displace;
      for(const variant of item.variants){
        const width=variant.width/scale, anchors=[];
        if(item.type==='object-label'){
          const f=item.footprint,center=(f.left+f.right)/2,y=f.top-gap-height/2;
          const offset=(f.right-f.left)/2;
          for(const dx of [0,-offset/2,offset/2,-offset,offset])anchors.push({x:center+dx,y});
        }else{
          for(const segment of item.segments){
            const x=(segment.a[0]+segment.b[0])/2,y=(segment.a[1]+segment.b[1])/2;
            anchors.push({x,y,segment});
          }
        }
        for(const anchor of anchors){
          const {x,y,segment}=anchor;
          const box={left:x-width/2,right:x+width/2,top:y-height/2,bottom:y+height/2};
          const candidate={...anchor,box,text:variant.text,visible:true};
          fallback??={...candidate,visible:false};
          if(segment && width+gap*2>Math.abs(segment.a[0]-segment.b[0]))continue;
          if(item.type==='edge-label'&&segments.some(other=>other!==segment&&intersects(other,box)))continue;
          const conflicts=occupied.filter(({box:b})=>box.left<b.right+gap&&box.right>b.left-gap&&
            box.top<b.bottom+gap-1e-8&&box.bottom>b.top-gap+1e-8);
          if(!conflicts.length){chosen=candidate;break;}
          if(item.id===subject&&!displace&&conflicts.every(entry=>entry.type==='area-label')){
            displace={candidate,conflicts};
          }
        }
        if(chosen||item.generic)break;
      }
      if(!chosen&&displace){
        chosen=displace.candidate;
        for(const entry of displace.conflicts){
          placements.get(entry.id).visible=false;
          occupied.splice(occupied.indexOf(entry),1);
        }
      }
      if(chosen&&item.generic)chosen.visible=false;
      if(chosen?.visible)occupied.push({id:item.id,type:item.type,box:chosen.box});
      placements.set(item.id,chosen||fallback);
    }
    return placements;
  }
  return {plan,objectScale,objectHalfExtent:clearance,placeCaptions};
})();
