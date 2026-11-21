/* Exercise the real Map controller/projection with a measured SVG host double. */
'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path');
require('../Sources/ArchitectureGraph/Resources/c4-layout.js');
require('../Sources/ArchitectureGraph/Resources/c4-objects.js');
class SVGHost {
 constructor(tag){this.tag=tag;this.attrs={};this.dataset={};this.children=[];this.style={};this.listeners=new Map();this.firstChild={data:''};this.clientWidth=800;this.clientHeight=600;this.classList={toggle(){},add(){},remove(){}};}
 set textContent(value){this.firstChild.data=String(value);this.children=[];}
 get textContent(){return this.firstChild.data;}
 setAttribute(key,value){this.attrs[key]=String(value);if(key.startsWith('data-'))this.dataset[key.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase())]=String(value);}
 removeAttribute(key){delete this.attrs[key];}
 append(...items){for(const item of items){item.parent=this;this.children.push(item);}}
 replaceChildren(...items){this.children=[];this.append(...items);}
 remove(){if(this.parent)this.parent.children=this.parent.children.filter(child=>child!==this);}
 querySelector(tag){for(const child of this.children){if(child.tag===tag)return child;const nested=child.querySelector(tag);if(nested)return nested;}return null;}
 addEventListener(type,callback){if(!this.listeners.has(type))this.listeners.set(type,[]);this.listeners.get(type).push(callback);}
 fire(type,extra={}){let stopped=false;const event={target:this,preventDefault(){},stopPropagation(){stopped=true;},...extra};for(const callback of this.listeners.get(type)||[])callback(event);return stopped;}
 getComputedTextLength(){return this.textContent.length*6;}
 getBBox(){return this.tag==='text'?{x:-this.getComputedTextLength()/2,y:-10,width:this.getComputedTextLength(),height:14}:{x:-20,y:-60,width:40,height:60};}
 cloneNode(){const copy=new SVGHost(this.tag);copy.attrs={...this.attrs};return copy;}
 getBoundingClientRect(){return {left:0,top:0,width:800,height:600};}
 matches(){return false;}
}
function setup(relations=false){
 const context={document:{createElementNS:(_,tag)=>new SVGHost(tag)},AbortController,matchMedia:()=>({matches:false,addEventListener(){}}),ResizeObserver:class{observe(){}disconnect(){}},requestAnimationFrame:()=>0,cancelAnimationFrame(){},C4Layout,C4Objects:{...C4Objects,renderSymbols(){}}};
 vm.createContext(context);
 const assets=path.join(__dirname,'../Sources/ArchitectureGraph/Resources');
 for(const file of ['three-c4.min.js','c4-map.js'])vm.runInContext(fs.readFileSync(path.join(assets,file),'utf8'),context);
 const host=new SVGHost('host'),calls=[];
 const node={id:'app',kind:'application',name:'Application',attributes:{'context.areas':[{id:'domain',name:'Domain'}]}};
 const nodes=relations?[node,{id:'store',kind:'dataStore',name:'Store'}]:[node];
 const edges=relations?[{id:'writes',source:'app',target:'store',kind:'dependsOn'}]:[];
 const map=new context.C4Map(host,{nodes,edges},{menu:(...args)=>calls.push(args),zoom(){},node(){throw Error('Opening options must not activate selection');},edge(){},expand(){},clear(){}});
 const descendants=element=>[element,...element.children.flatMap(descendants)];
 return {map,calls,all:()=>descendants(host)};
}
test('Map report access stays in object and caption context menus without standalone report controls',()=>{
 const {map,calls,all}=setup();const camera=[map.cx,map.cy,map.scale];
 const object=map.targets.get('app');
 object.fire('contextmenu',{clientX:120,clientY:80});
 assert.equal(calls.length,1);assert.equal(calls[0][0],object);assert.equal(calls[0][1].id,'app');
 assert.equal(calls[0][2].x,120);assert.equal(calls[0][2].y,80);
 object.fire('keydown',{key:'F10',shiftKey:true});assert.equal(calls.length,2);
 const caption=all().find(el=>el.dataset.owner==='app');
 caption.fire('contextmenu',{clientX:150,clientY:90});
 assert.equal(calls.length,3);assert.equal(calls[2][0],caption);assert.equal(calls[2][1].id,'app');
 assert.ok(!all().some(el=>(el.attrs.class||'').includes('c4-report')));
 assert.ok(!all().some(el=>/^Reports?$/.test(el.textContent)));
 assert.deepEqual([map.cx,map.cy,map.scale],camera);map.dispose();
});
test('the arrow is attached to the single visible and selectable route',()=>{
 const {map}=setup(true);
 const edge=map.targets.get('writes');
 const lines=edge.children.filter(child=>child.tag==='path'&&child.attrs.class==='c4-line');
 assert.deepEqual(lines,[edge.route]);
 assert.equal(edge.route.attrs['marker-end'],'url(#c4-arrow)');
 assert.equal(edge.children.find(child=>child.attrs.class==='c4-hit').attrs.d,edge.route.attrs.d);
 assert.equal(map.svg.querySelector('marker').attrs.refX,'10');
 map.dispose();
});
