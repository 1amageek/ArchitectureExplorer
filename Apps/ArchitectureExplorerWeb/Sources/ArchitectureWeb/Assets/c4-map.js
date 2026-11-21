// One orthographic coordinate system for interactive SVG, including offline exports.
globalThis.C4Map = class {
  constructor(host, view, actions) {
    this.host=host;
    this.actions=actions;
    this.abort=new AbortController();
    const signal=this.abort.signal;
    this.motion=matchMedia('(prefers-reduced-motion: reduce)');
    this.theme=matchMedia('(prefers-color-scheme: dark)');
    this.selected=null;
    this.targets=new Map();
    this.labels=[];
    const svg=(tag,attrs={},parent=this.svg)=>{
      const element=document.createElementNS('http://www.w3.org/2000/svg',tag);
      for(const [k,v] of Object.entries(attrs))element.setAttribute(k,v);
      parent?.append(element);
      return element;
    };
    this.svg=svg('svg',{class:'c4-map',role:'group','aria-label':'Map'});
    host.replaceChildren(this.svg);
    const T=C4Three;
    const camera=new T.OrthographicCamera(-50,50,50,-50,0.1,10000);
    camera.position.set(100,100,100);camera.lookAt(0,0,0);camera.updateMatrixWorld();
    const project=(x,z,y=0)=>{
      const v=new T.Vector3(x*24,y,z*24).applyMatrix4(camera.matrixWorldInverse);
      return [v.x,-v.y];
    };
    const defs=svg('defs');
    const pattern=svg('pattern',{id:'c4-grid',patternUnits:'userSpaceOnUse',width:Math.sqrt(2)*24,height:48/Math.sqrt(6)},defs);
    const w=Math.sqrt(2)*24,h=48/Math.sqrt(6);
    svg('path',{d:'M0,0 L'+w+','+h+' M0,'+h+' L'+w+',0',class:'c4-grid'},pattern);
    const marker=svg('marker',{id:'c4-arrow',viewBox:'0 0 10 10',refX:10,refY:5,markerWidth:5,markerHeight:5,orient:'auto'},defs);
    svg('path',{d:'M0 0 L10 5 L0 10 Z',fill:'context-stroke'},marker);
    const glyphs=svg('g',{},defs);
    const subject=view.extensions?.['c4.container']?.subject;
    this.subject=subject;
    const visible=new Set(view.nodes.map(n=>n.id));
    const nodes=[...view.nodes,...(actions.overview||[]).filter(n=>!visible.has(n.id))];
    const plan=C4Layout.plan(nodes,view.edges,subject);
    const visibleAreas=plan.visibleAreas(visible);
    const roles=new Map(plan.objects.filter(item=>visible.has(item.id))
      .map(item=>[item.id,C4Objects.resolve(item.node)]));
    const buildGlyphs=()=>C4Objects.renderSymbols(glyphs,roles.values(),camera,this.theme.matches);
    buildGlyphs();this.theme.addEventListener('change',buildGlyphs,{signal});
    this.grid=svg('rect',{fill:'url(#c4-grid)','pointer-events':'none'});
    const areas=svg('g'),routes=svg('g'),objects=svg('g'),captions=svg('g');
    const title=(parent,value)=>{svg('title',{},parent).textContent=value;};
    const bindMenu=(target,node)=>{
      if(!actions.menu||!node)return;
      const menu=(event,point)=>{
        event.preventDefault();
        actions.menu(target,node,point);
      };
      target.addEventListener('contextmenu',event=>menu(event,{x:event.clientX,y:event.clientY}));
      target.addEventListener('keydown',event=>{if(event.key==='ContextMenu'||(event.shiftKey&&event.key==='F10'))menu(event);});
    };
    const register=(id,group,activate,expand)=>{
      group.dataset.id=id;
      group.setAttribute('tabindex','0');
      group.setAttribute('role','button');
      group.addEventListener('click',activate);
      group.addEventListener('keydown',event=>{
        if(event.key==='Enter'||event.key===' '){event.preventDefault();activate();}
      });
      if(expand)group.addEventListener('dblclick',expand);
      this.targets.set(id,group);
    };
    // Shapes and captions are in separate SVG layers, but share a hover identity.
    const hoverItems=new Map();
    const describe=(group,id,name)=>{
      group.dataset.hoverId=id;
      group.setAttribute('aria-label',name);
      title(group,name);
      hoverItems.set(id,{group,name});
    };
    const candidates=[];
    const label=(id,name,type,click,geometry,node)=>{
      const el=svg('text',{class:'c4-label '+type,'text-anchor':'middle'},captions);
      el.textContent=name;el.dataset.owner=id;el.addEventListener('click',click);
      bindMenu(el,node);
      candidates.push({el,id,name,type,...geometry});
    };
    const bounds=[];
    for(const item of plan.areas){
      if(!visibleAreas.has(item.id))continue;
      const {x,z,width,depth}=item;
      const points=[[x,z],[x+width,z],[x+width,z+depth],[x,z+depth]].map(p=>project(...p));
      bounds.push(...points);
      const g=svg('g',{},areas);
      describe(g,item.id,item.name);
      svg('polygon',{points:points.join(' '),class:'c4-area'},g);
      const node=view.nodes.find(n=>n.id===item.id);
      if(node){register(item.id,g,()=>actions.node(node));bindMenu(g,node);}
      else {g.setAttribute('role','group');g.setAttribute('tabindex','0');}
      const outline=svg('path',{class:'c4-boundary','pointer-events':'none'},g);
      const segments=[2,1].map(i=>({a:points[i],b:points[i+1]}));
      label(item.id,item.name,'area-label',()=>{if(node)actions.node(node);},{corners:points,outline,segments},node);
    }
    for(const {edge,points} of plan.paths){
      const projected=points.map(p=>project(...p));
      const d='M'+projected.join(' L');
      const g=svg('g',{class:'c4-route'},routes);
      const path=svg('path',{d,class:'c4-line','marker-end':'url(#c4-arrow)'},g);
      svg('path',{d,class:'c4-hit'},g);
      const name=edge.attributes?.['context.operation']||edge.kind;
      describe(g,edge.id,name);
      hoverItems.get(edge.id).endpoints=[edge.source,edge.target];
      register(edge.id,g,()=>actions.edge(edge));
      g.route=path;
      const segments=projected.slice(1).map((b,i)=>({a:projected[i],b}));
      const length=s=>Math.hypot(s.a[0]-s.b[0],s.a[1]-s.b[1]);
      segments.sort((a,b)=>length(b)-length(a));
      const normalized=value=>value.toLowerCase().replace(/\s/g,'');
      const generic=normalized(name)===normalized(edge.kind);
      label(edge.id,name,'edge-label',()=>actions.edge(edge),{segments,generic});
    }
    // The footprint uses the same ground coordinates as route clearance.
    // Its parent scales the glyph, so express the projected corners in glyph units.
    const extent=C4Layout.objectHalfExtent;
    const scale=C4Layout.objectScale;
    const footprintPoints=[[-extent,-extent],[extent,-extent],[extent,extent],[-extent,extent]]
      .map(([x,z])=>project(x,z).map(value=>value/scale).join(',')).join(' ');
    const occupied=[];
    for(const item of plan.objects){
      if(!visible.has(item.id))continue;
      const n=item.node, p=project(...plan.positions.get(n.id));
      const g=svg('g',{class:'c4-object',transform:'translate('+p.join(' ')+') scale('+scale+')'},objects);
      describe(g,n.id,n.name);
      svg('polygon',{points:footprintPoints,class:'c4-footprint'},g);
      svg('ellipse',{cx:0,cy:0,rx:22,ry:12,class:'c4-foot','pointer-events':'none'},g);
      const role=roles.get(n.id);
      svg('use',{href:'#c4-shape-'+role},g);
      register(n.id,g,()=>actions.node(n),()=>actions.expand(n));
      bindMenu(g,n);
      const box=g.getBBox();
      const top=p[1]+box.y*scale;
      const left=p[0]+box.x*scale,right=left+box.width*scale,bottom=top+box.height*scale;
      const footprint={left,right,top,bottom};
      occupied.push(footprint);
      bounds.push([left,top],[right,bottom]);
      label(n.id,n.name,'object-label',()=>actions.node(n),{footprint},n);
    }
    // Measure once at screen font size. Pan only moves the camera; zoom changes the available space.
    const priority={'object-label':0,'area-label':1,'edge-label':2};
    candidates.sort((a,b)=>priority[a.type]-priority[b.type]);
    for(const c of candidates){
      const textNode=c.el.firstChild;
      const letters=Array.from(c.name);
      const strings=[c.name];
      if(c.type==='object-label'){
        for(const limit of [28,18,12,8,5,3,1]){
          if(letters.length>limit+1)strings.push(letters.slice(0,limit).join('')+'…');
        }
      }
      c.variants=strings.map(value=>{
        textNode.data=value;
        return {text:value,width:c.el.getComputedTextLength()};
      });
      textNode.data=c.name;
      const box=c.el.getBBox();
      c.height=box.height;
      c.baseline=-box.y-box.height/2;
      title(c.el,c.name);
      c.el.dataset.hoverId=c.id;
      Object.assign(hoverItems.get(c.id),{caption:c});
      this.labels.push(c.el);
    }
    function drawOutline(c,segment,width){
      // The floor remains one hit region. Only its own stroked perimeter has a gap.
      let path='M'+c.corners[0].join(' ');
      c.corners.forEach((a,i)=>{
        const b=c.corners[(i+1)%4];
        if(width&&segment?.a===a){
          const half=Math.min(.48,width/(2*Math.abs(b[0]-a[0])));
          const at=t=>[a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t].join(' ');
          path+=' L'+at(.5-half)+' M'+at(.5+half);
        }
        path+=' L'+b.join(' ');
      });
      c.outline.setAttribute('d',path);
    }
    let hovered,pointed,focused;
    // A separate, non-interactive copy paints the full title over surrounding captions.
    const foreground=svg('g',{'pointer-events':'none'});
    const activeTitles=new Map();
    const refreshCaption=id=>{
      const c=hoverItems.get(id)?.caption;
      if(!c?.placement)return;
      const p=c.placement,active=id===hovered||(id===this.selected&&c.type==='edge-label');
      c.el.style.visibility=p.visible||active?'visible':'hidden';
      c.el.firstChild.data=active?c.name:p.text;
      c.el.classList.toggle('c4-hover',id===hovered);
      activeTitles.get(id)?.remove();
      activeTitles.delete(id);
      if(active){
        const copy=c.el.cloneNode(false);
        copy.removeAttribute('data-hover-id');copy.removeAttribute('data-owner');
        copy.setAttribute('aria-hidden','true');copy.textContent=c.name;
        foreground.append(copy);activeTitles.set(id,copy);
      }
      if(c.outline){
        const width=active?c.variants[0].width/this.scale:p.box.right-p.box.left;
        drawOutline(c,p.segment,p.visible||active?width+6/this.scale:0);
      }
    };
    this.layoutCaptions=()=>{
      const placements=C4Layout.placeCaptions(candidates,occupied,this.scale,subject);
      for(const c of candidates){
        const p=placements.get(c.id);
        c.placement=p;
        c.el.setAttribute('transform','translate('+p.x+' '+p.y+') scale('+1/this.scale+')');
        c.el.setAttribute('y',c.baseline);
        refreshCaption(c.id);
      }
    };
    const emphasize=(id,active,style)=>{
      const item=hoverItems.get(id);
      if(!item)return;
      item.group.classList.toggle(style,active);
      for(const endpoint of item.endpoints||[]){
        this.targets.get(endpoint)?.classList.toggle(style+'-endpoint',active);
      }
      refreshCaption(id);
    };
    this.selectedCaption=(id,active)=>emphasize(id,active,'c4-selected');
    const updateHover=()=>{
      const id=pointed??focused;
      if(id===hovered)return;
      const previous=hovered;hovered=id;
      emphasize(previous,false,'c4-hover');emphasize(id,true,'c4-hover');
    };
    const owner=target=>target?.closest?.('[data-hover-id]')?.dataset.hoverId;
    this.svg.addEventListener('pointerover',event=>{
      if(event.pointerType==='touch')return;
      pointed=owner(event.target);updateHover();
    },{signal});
    this.svg.addEventListener('pointerout',event=>{
      if(event.pointerType==='touch')return;
      pointed=owner(event.relatedTarget);updateHover();
    },{signal});
    this.svg.addEventListener('focusin',event=>{
      focused=event.target.matches(':focus-visible')?owner(event.target):undefined;
      if(focused)pointed=undefined;
      updateHover();
    },{signal});
    this.svg.addEventListener('focusout',()=>{focused=undefined;updateHover();},{signal});
    this.bounds=bounds.length?bounds:[[0,0],[100,100]];
    this.dot=svg('circle',{r:3.5,class:'c4-pulse',visibility:'hidden','pointer-events':'none'});
    this.motion.addEventListener('change',()=>this.animate(),{signal});
    this.observer=new ResizeObserver(()=>this.paint());
    this.observer.observe(host);
    this.fit();
    const local=e=>{const r=this.svg.getBoundingClientRect();return [e.clientX-r.left,e.clientY-r.top];};
    this.svg.addEventListener('click',event=>{
      if(!event.target.closest('[data-id],[data-owner]'))actions.clear();
    },{signal});
    this.svg.addEventListener('wheel',e=>{
      e.preventDefault();
      const unit=e.deltaMode===1?16:e.deltaMode===2?host.clientHeight:1;
      if(e.metaKey||e.ctrlKey)this.zoomBy(Math.exp(-e.deltaY*unit*.01),local(e));
      else {this.cx+=e.deltaX*unit/this.scale;this.cy+=e.deltaY*unit/this.scale;this.paint();}
    },{passive:false,signal});
    let gesture,drag;
    this.svg.addEventListener('gesturestart',e=>{e.preventDefault();gesture=this.scale;},{passive:false,signal});
    this.svg.addEventListener('gesturechange',e=>{e.preventDefault();if(gesture)this.zoomBy(gesture*e.scale/this.scale,local(e));},{passive:false,signal});
    this.svg.addEventListener('gestureend',e=>{e.preventDefault();gesture=null;},{passive:false,signal});
    this.svg.addEventListener('pointerdown',e=>{
      if(e.button!==0||e.target.closest('[data-id],text'))return;
      this.svg.setPointerCapture(e.pointerId);drag=local(e);
    },{signal});
    this.svg.addEventListener('pointermove',e=>{
      if(!drag)return;const p=local(e);this.cx+=(drag[0]-p[0])/this.scale;
      this.cy+=(drag[1]-p[1])/this.scale;drag=p;this.paint();
    },{signal});
    for(const name of ['pointerup','pointercancel','lostpointercapture'])this.svg.addEventListener(name,()=>{drag=null;},{signal});
  }
  fit(){
    const xs=this.bounds.map(p=>p[0]),ys=this.bounds.map(p=>p[1]);
    const l=Math.min(...xs),r=Math.max(...xs),t=Math.min(...ys),b=Math.max(...ys);
    this.cx=(l+r)/2;this.cy=(t+b)/2;
    this.scale=Math.max(.02,Math.min(2,(this.host.clientWidth-32)/(r-l+48),(this.host.clientHeight-80)/(b-t+48)));
    this.paint();
  }
  paint(){
    const w=Math.max(1,this.host.clientWidth)/this.scale,h=Math.max(1,this.host.clientHeight)/this.scale;
    const x=this.cx-w/2,y=this.cy-h/2;
    this.svg.setAttribute('viewBox',[x,y,w,h].join(' '));
    for(const [k,v] of Object.entries({x,y,width:w,height:h}))this.grid.setAttribute(k,v);
    if(this.captionScale!==this.scale){
      this.captionScale=this.scale;this.layoutCaptions();
    }
    this.actions.zoom(this.scale);
  }
  zoomBy(factor,at=[this.host.clientWidth/2,this.host.clientHeight/2]){
    const next=Math.max(.02,Math.min(8,this.scale*factor));
    this.cx+=(at[0]-this.host.clientWidth/2)*(1/this.scale-1/next);
    this.cy+=(at[1]-this.host.clientHeight/2)*(1/this.scale-1/next);
    this.scale=next;this.paint();
  }
  select(id){
    const previous=this.selected;
    this.targets.get(previous)?.classList.remove('selected');
    this.selected=id;this.targets.get(id)?.classList.add('selected');
    for(const l of this.labels)l.classList.toggle('selected',l.dataset.owner===id);
    this.selectedCaption(previous,false);this.selectedCaption(id,true);
    this.animate();
  }
  animate(){
    cancelAnimationFrame(this.frame);this.dot.setAttribute('visibility','hidden');
    const path=this.targets.get(this.selected)?.route;
    if(!path||this.motion.matches)return;
    const length=path.getTotalLength();if(!length)return;
    const start=performance.now();
    const tick=now=>{
      const p=path.getPointAtLength(((now-start)*.085)%length);
      this.dot.setAttribute('cx',p.x);this.dot.setAttribute('cy',p.y);
      this.dot.setAttribute('visibility','visible');this.frame=requestAnimationFrame(tick);
    };
    this.frame=requestAnimationFrame(tick);
  }
  dispose(){this.abort.abort();this.observer.disconnect();cancelAnimationFrame(this.frame);this.host.replaceChildren();}
};
