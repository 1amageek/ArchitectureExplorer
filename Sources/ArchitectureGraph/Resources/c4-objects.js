// Reusable Three.js objects for both live and saved isometric diagrams.
// Each factory is centered on the floor port and fits the map's shared footprint.
globalThis.C4Objects = (() => {
  const components = {
    person({box, sphere}) {
      for (const x of [-4.6,4.6]) box(8,5,11,x,2.5,2,'navy');
      box(16,14,11,0,11,0,'teal');
      sphere(8,0,23,0,'cream');
      for (const x of [-3,3]) sphere(1,x,23,7,'navy');
    },
    softwareSystem({box, cylinder}) {
      box(30,4,23,0,2,0,'cream');
      box(13,17,15,-7,12,0,'blue');
      cylinder(3.6,3.6,2.5,-7,21.5,0,'blue');
      box(12,10,13,6.5,9,2,'yellow');
      cylinder(3.4,3.4,2,6.5,15,2,'yellow');
    },
    application({box, cylinder}) {
      box(27,13,21,0,6.5,0,'blue');
      box(25,3,19,0,14,0,'cream');
      cylinder(4,4,2.5,4,16.5,0,'coral');
    },
    webApp({box, sphere}) {
      box(20,4,13,0,2,0,'teal');
      box(6,5,5,0,6,0,'teal');
      box(30,21,7,0,17,0,'teal');
      box(28,20,2,0,17,4,'cream');
      box(23,13,1.5,0,18,5.4,'screen');
      sphere(1.25,9,9.8,5.2,'coral');
    },
    mobileApp({box, sphere}) {
      box(17,28,5,0,14,0,'violet');
      box(13,19,1.2,0,15.5,2.9,'screen');
      sphere(1.4,0,3.5,2.6,'cream');
    },
    service({box, sphere}) {
      for (const y of [5,16]) {
        box(28,10,20,0,y,0,'teal');
        box(15,2.8,1,-3,y,10,'navy');
        sphere(1.8,9,y,10,'yellow');
      }
    },
    worker({box, cylinder}) {
      box(25,4,18,0,2,0,'blue');
      cylinder(9,9,17,0,12,0,'yellow',Math.PI/2);
      cylinder(9.5,9.5,3,0,12,8,'coral',Math.PI/2);
      cylinder(3.8,3.8,6,0,12,11,'blue',Math.PI/2);
    },
    gateway({box}) {
      box(28,4,16,0,2,0,'teal');
      for (const x of [-10,10]) box(7,18,10,x,11,0,'yellow');
      box(28,7,11,0,21,0,'coral');
    },
    database({cylinder}) {
      cylinder(13,13,15,0,10,0,'violet');
      for (const y of [3.5,12,20.5]) cylinder(15,15,7,0,y,0,'blue');
      cylinder(4.5,5.2,2,0,24.5,0,'cream');
    },
    cache({box}) {
      for (const x of [-6,0,6]) box(3,3,24,x,2,0,'yellow');
      for (const z of [-5,0,5]) box(27,3,3,0,2,z,'yellow');
      box(21,7,18,0,5,0,'navy');
      box(16,4,14,0,10,0,'violet');
    },
    messageQueue({box}) {
      box(30,4,17,0,2,0,'cream');
      ['coral','yellow','teal','blue'].forEach((tone,i)=>box(4,15,13,-11+i*7,10,0,tone));
    },
    objectStorage({cylinder, handle}) {
      handle(13,16,'yellow');
      cylinder(14,10,18,0,9,0,'coral');
      cylinder(15,15,3,0,19,0,'coral');
      cylinder(11.5,11.5,.7,0,20.6,0,'navy');
    },
    dataArtifact({box}) {
      ['teal','yellow','cream'].forEach((tone,i)=>box(22,3,24,i-1,1.5+i*3.5,1-i,tone));
      box(9,1,4,-4,10.4,-7,'coral');
      for (const z of [0,5]) box(13,.8,1.8,0,10.4,z,'blue');
    },
    dataStore({cylinder}) {
      cylinder(14,14,19,0,9.5,0,'violet');
    },
    unknown({box}) {
      box(18,5,18,0,2.5,0,'cream');
    }
  };

  const applications = new Map([
    ['service', 'service'], ['website', 'webApp'], ['mobile-app', 'mobileApp'],
    ['worker', 'worker'], ['api-gateway', 'gateway']
  ]);
  const stores = new Map([
    ['database', 'database'], ['cache', 'cache'], ['queue', 'messageQueue'],
    ['object-storage', 'objectStorage']
  ]);

  function resolve(node) {
    const type = node.attributes?.['context.catalogType'];
    switch (node.kind) {
      case 'application': return applications.get(type) || 'application';
      case 'dataStore': return stores.get(type) || 'dataStore';
      case 'softwareSystem': return stores.get(type) || 'softwareSystem';
      case 'person': case 'dataArtifact': return node.kind;
      default: return 'unknown';
    }
  }

  const ns = 'http://www.w3.org/2000/svg';
  function svg(parent, tag, attributes) {
    const el = document.createElementNS(ns, tag);
    for (const [name,value] of Object.entries(attributes)) el.setAttribute(name,value);
    parent.append(el);
    return el;
  }

  // One finish per surface type. Ramps are continuous across a curved wall.
  function defineFinishes(defs, dark) {
    const paints = {};
    function gradient(name, stops, direction = {x2:'0%', y2:'100%'}, radial = false) {
      const id = 'c4-finish-'+name;
      const g = svg(defs,radial?'radialGradient':'linearGradient',{id,...direction});
      for (const [offset,color,opacity=1] of stops) {
        svg(g,'stop',{offset,'stop-color':color,'stop-opacity':opacity});
      }
      paints[name]='url(#'+id+')';
    }
    // One family of molded finishes under a broad upper-left light.
    const plastics = {
      blue:   ['#b6dfff','#639fec','#3878cf','#294f95','#3a629e'],
      teal:   ['#c0f1df','#65c7ac','#369d90','#216b70','#367c7e'],
      yellow: ['#fff1ac','#ffd35e','#eda535','#ad682a','#bb7837'],
      coral:  ['#ffd8b8','#ff987a','#e26f61','#a74946','#b85953'],
      violet: ['#e3d6ff','#b59be1','#8c74bf','#5b538b','#70669e'],
      cream:  ['#fff9e9','#f2e6c9','#d5c6a9','#a99b88','#b4a792'],
      navy:   ['#8093ab','#515f7a','#364359','#273449','#334156'],
      screen: ['#b4eff3','#77c3d2','#478baf','#356489','#427696']
    };
    for (const [name, [lit, base, mid, shadow, ambientShadow]] of Object.entries(plastics)) {
      // A small ambient fill keeps the shaded sides legible on the dark canvas.
      const shade = dark ? ambientShadow : shadow;
      gradient(name+'Cap',[[0,lit],[.36,base],[1,mid]],{x2:'78%',y2:'100%'});
      gradient(name+'Face',[[0,base],[.64,mid],[1,shade]],{x2:'65%',y2:'100%'});
      gradient(name+'Wall',[[0,mid],[.23,base],[.65,mid],[1,shade]],{x2:'95%',y2:'28%'});
      gradient(name+'Ball',[[0,lit],[.3,base],[.74,mid],[1,shade]],{cx:'.34',cy:'.25',r:'.78'},true);
    }
    gradient('contact',[[0,'#13191d',dark ? .58 : .25],[.55,'#13191d',dark ? .32 : .13],[1,'#13191d',0]],
      {cx:'.5',cy:'.5',r:'.5'},true);
    return paints;
  }

  function hull(points) {
    const sorted=points.sort(([x,y],[u,v])=>x-u||y-v);
    const cross=(a,b,c)=>(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
    function chain(sequence){
      const result=[];
      for(const p of sequence){
        while(result.length>1&&cross(result.at(-2),result.at(-1),p)<=0)result.pop();
        result.push(p);
      }
      result.pop();
      return result;
    }
    return [...chain(sorted),...chain(sorted.reverse())];
  }

  function primitives(symbol, camera, paint) {
    const view = new C4Three.Vector3();
    camera.getWorldDirection(view).negate();
    const point = new C4Three.Vector3();
    function project(x,y,z) {
      point.set(x,y,z).applyMatrix4(camera.matrixWorldInverse);
      return [Number(point.x.toFixed(3)),Number((-point.y).toFixed(3))];
    }
    function surface(points, fill, rim) {
      const attrs={d:'M'+points.join(' L')+' Z',fill};
      if(rim)Object.assign(attrs,{stroke:rim,'stroke-width':.28,'stroke-linejoin':'round'});
      return svg(symbol,'path',attrs);
    }
    function box(w,h,d,x,y,z,tone) {
      // Extrude a rounded rectangle on the broadest face. Painting a continuous
      // hull keeps its fillets smooth even in the smallest overview.
      const sizes=[w,h,d],depth=sizes.indexOf(Math.min(...sizes));
      const u=(depth+1)%3,v=(depth+2)%3;
      const a=sizes[u]/2,b=sizes[v]/2,r=Math.min(3.6,a*.65,b*.65);
      const front=[],back=[];
      for(let corner=0;corner<4;corner++){
        const cx=corner===0||corner===3?a-r:r-a,cy=corner<2?b-r:r-b;
        for(let k=0;k<=6;k++){
          const angle=(corner+k/6)*Math.PI/2;
          const p=[x,y,z];
          p[u]+=cx+r*Math.cos(angle);p[v]+=cy+r*Math.sin(angle);
          p[depth]+=sizes[depth]/2;
          front.push(project(...p));
          p[depth]-=sizes[depth];
          back.push(project(...p));
        }
      }
      surface(hull([...front,...back]),paint[tone+'Wall']);
      surface(front,paint[tone+(depth===1?'Cap':'Face')],'#ffffff70');
    }
    function cylinder(rt,rb,h,x,y,z,tone,tilt=0) {
      const cos=Math.cos(tilt),sin=Math.sin(tilt);
      const along=view.y*cos+view.z*sin,across=view.z*cos-view.y*sin;
      const facing=Math.atan2(across,view.x);
      const arc=(radius,dy,start,length,count)=>Array.from({length:count+1},(_,i)=>{
        const angle=start+length*i/count,dx=radius*Math.cos(angle),dz=radius*Math.sin(angle);
        return project(x+dx,y+dy*cos-dz*sin,z+dy*sin+dz*cos);
      });
      const start=facing-Math.PI/2;
      // Inset caps and rolled shoulders soften both rims of a stacking piece.
      const lip=Math.min(1.5,h*.24,rt*.18,rb*.18);
      const top=arc(rt-lip,h/2,start,2*Math.PI,48),bottom=arc(rb-lip,-h/2,start,2*Math.PI,48);
      const upper=arc(rt,h/2-lip,start,2*Math.PI,48),lower=arc(rb,-h/2+lip,start,2*Math.PI,48);
      surface(hull([...bottom,...top,...upper,...lower]),paint[tone+'Wall']);
      const cap=along>=0?top:bottom;
      const shoulder=along>=0?upper:lower;
      surface(hull([...cap,...shoulder]),paint[tone+'Face']);
      surface(cap,paint[tone+'Cap'],'#ffffff70');
    }
    function sphere(radius,x,y,z,tone) {
      const [cx,cy]=project(x,y,z);
      svg(symbol,'circle',{cx,cy,r:radius,fill:paint[tone+'Ball']});
    }
    function handle(radius,y,tone) {
      const points=Array.from({length:33},(_,i)=>{
        const angle=i*Math.PI/32;
        return project(radius*Math.cos(angle),y+radius*Math.sin(angle),0);
      });
      svg(symbol,'path',{d:'M'+points.join(' L'),fill:'none',stroke:paint[tone+'Face'],
        'stroke-width':2.8,'stroke-linecap':'round','stroke-linejoin':'round'});
    }
    return {box,cylinder,sphere,handle};
  }

  function renderSymbols(parent, roles, camera, dark) {
    const symbols=document.createDocumentFragment();
    const defs=svg(symbols,'defs',{});
    const finishes=defineFinishes(defs,dark);
    for(const role of new Set(roles)){
      const symbol=svg(symbols,'g',{id:'c4-shape-'+role});
      components[role](primitives(symbol,camera,finishes));
    }
    parent.replaceChildren(symbols);
  }
  return Object.freeze({resolve, renderSymbols});
})();
