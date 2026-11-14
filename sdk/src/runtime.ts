import {signal, computed, effect as reactiveEffect, batch, Signal} from '@preact/signals-core';
export {signal, computed, batch};
let owner:(()=>void)[]|null=null;
export function effect(fn:()=>void|(()=>void)){const dispose=reactiveEffect(fn);owner?.push(dispose);return dispose;}
type Descriptor = {type: any; props: any; children: any[]};
type Node = {id:string; mountID:number; type:string; props:any; children:string[]};
const nodes = new Map<string,Node>();
const descriptions = new Map<string,any>();
const disposers = new Map<string,(()=>void)[]>();
const handlers = new Map<string,(event:any)=>void>();
const requests = new Map<string,{resolve:Function;reject:Function}>();
const subscriptions = new Map<string,ReturnType<typeof signal>>();
const edits = new Map<string,number>();
const draftKeys = new WeakMap<object,string>();
const patches = new Map<string,any>();
let outbox:any[] = [], requestID=0, mountID=0, root:string|null=null, initialized=false;
let draft:any={}, revision=0;
const reading=(value:any)=>value instanceof Signal ? value.value : typeof value==='function' ? value() : value;
const changed=(a:any,b:any)=>JSON.stringify(a)!==JSON.stringify(b);
function bounded() { if(nodes.size>512 || outbox.length>128 || requests.size>64) throw Error('App resource limit exceeded'); }
function send(message:any) {
 if(message.kind==='draft'){const existing=outbox.findIndex(m=>m.kind==='draft');if(existing>=0)outbox[existing]=message;else outbox.push(message);}
 else outbox.push(message);bounded();
}
function update(node:Node) { patches.set(node.id,{op:'put',node:{...node,props:{...node.props},children:[...node.children]}}); bounded(); }
export function h(type:any, props:any,...children:any[]):Descriptor { return {type,props:props||{},children:children.flat()}; }
export const Fragment='column';
export const Column='column', Row='row', Grid='grid', Split='split', Scroll='scroll', Section='section';
export const Text='text', Button='button', TextField='textField', TextEditor='textEditor', Toggle='toggle';
export const Picker='picker', Slider='slider', DatePicker='date', Progress='progress', Table='table';
export const Tabs='tabs', Disclosure='disclosure', Canvas='canvas', Image='image', Spacer='spacer';
function cleanup(id:string) {
 const node=nodes.get(id); if(!node)return;
 for(const dispose of disposers.get(id)||[])dispose();
 for(const child of [...node.children])cleanup(child);
 for(const key of [...handlers.keys()])if(key.startsWith(id+':'))handlers.delete(key);
 disposers.delete(id);nodes.delete(id);descriptions.delete(id);edits.delete(id);patches.set(id,{op:'remove',id});
}
function mountNode(description:any,id:string,depth=0):string {
 if(depth>24)throw Error('App layout is too deeply nested');
 descriptions.set(id,description);
 const previousOwner=owner, owned:(()=>void)[]=[];owner=owned;
 if(description===null || description===false || description===undefined)description=h(Spacer,{});
 if(typeof description==='string'||typeof description==='number')description=h(Text,{text:String(description)});
 let expansions=0;while(typeof description.type==='function'){if(++expansions>24)throw Error('Component nesting limit');description=description.type({...description.props,children:description.children});}
 if(!description || typeof description.type!=='string')throw Error('Expected a native component');
 const node:Node={id,mountID:++mountID,type:description.type,props:{},children:[]};nodes.set(id,node);disposers.set(id,owned);
 const scopes=disposers.get(id)!;
 for(const [key,value] of Object.entries(description.props)) {
  if(key==='key')continue;
  if(key.startsWith('on')) { if(typeof value!=='function')throw Error('Event handlers must be functions');handlers.set(id+':'+key,value as any);continue; }
  scopes.push(reactiveEffect(()=>{
   const next=reading(value);
   if(changed(node.props[key],next)){node.props[key]=next;node.props.editRevision=edits.get(id)||0;update(node);}
  }));
 }
 const valueSignal=description.props.value;
 if(valueSignal instanceof Signal){handlers.set(id+':bind',(event:any)=>{valueSignal.value=event.value;});const key=draftKeys.get(valueSignal);if(key)node.props.draftKey=key;}
 const children=description.children.length ? description.children : description.props.children||[];
 scopes.push(reactiveEffect(()=>{
  const list=(Array.isArray(children)?children:[children]).flatMap((child:any)=>{
   const actual=reading(child);return Array.isArray(actual)?actual:[actual];
  }).filter((child:any)=>child!==null && child!==undefined && child!==false);
  const keys=new Set<string>();
  const ids=list.map((child:any,index:number)=>{
   const key=String(child?.props?.key??index);
   if(keys.has(key))throw Error('Sibling keys must be unique');keys.add(key);
   const childID=id+'/'+encodeURIComponent(key);
   // Stable keyed lists use For, which updates each row's signal without replacing its scope.
   if(nodes.has(childID) && descriptions.get(childID)!==child)cleanup(childID);
   if(!nodes.has(childID))mountNode(child,childID,depth+1);
   return childID;
  });
  for(const childID of node.children)if(!ids.includes(childID))cleanup(childID);
  if(changed(node.children,ids)){node.children=ids;update(node);}
 }));
 update(node);owner=previousOwner;return id;
}
/** Retains each keyed child's signals and handlers while its row value changes. */
export function For(props:any):Descriptor {
 const cache=new Map<string,{value:ReturnType<typeof signal>;view:any}>();
 const renderer=props.children[0];
 return h(props.layout||Column,{gap:props.gap??0},()=>{
  const values=reading(props.each)||[];
  const seen=new Set<string>();
  const result=values.map((value:any)=>{
   const key=String(props.by(value));if(seen.has(key))throw Error('List keys must be unique');seen.add(key);
   let entry=cache.get(key);
   if(!entry){const item=signal(value);entry={value:item,view:renderer(item)};entry.view.props={...entry.view.props,key};cache.set(key,entry);}
   else if(changed(entry.value.peek(),value))entry.value.value=value;
   return entry.view;
  });
  for(const key of cache.keys())if(!seen.has(key))cache.delete(key);
  return result;
 });
}
export function mount(view:any) { if(root)throw Error('Mount one app root');root=mountNode(typeof view==='function'?h(view,{}):view,'root'); }
export function draftSignal(key:string,initial:any) {
 if(!key || key.length>128)throw Error('Use a short draft key');
 const value=signal(Object.hasOwn(draft,key)?draft[key]:initial);
 draftKeys.set(value,key);
 effect(()=>{draft[key]=value.value;send({kind:'draft',values:{...draft}});});return value;
}
function request(method:string,args:any):Promise<any> {
 const id=String(++requestID);send({kind:'request',id,method,args});
 return new Promise((resolve,reject)=>{requests.set(id,{resolve,reject});bounded();});
}
export const data={
 page:(table:string,options:any={})=>request('page',{table,...options}),
 query:(query:any)=>request('query',query),
 transaction:async(operations:any[],options:any={})=>{
  const result=await request('transaction',{operations,revision:options.revision??revision,token:options.token||('op-'+Date.now()+'-'+Math.random())});
  revision=Math.max(revision,result.revision);return result;
 },
 undo:async(receipt:any)=>request('transaction',{operations:[],undo:receipt.token,revision,token:'undo-'+Date.now()+'-'+Math.random()}),
};
export function liveQuery(query:any,kind:'page'|'query'='page') {
 const value=signal<any>({loading:true,rows:[],revision:0,error:null});const id='s'+(++requestID);
 subscriptions.set(id,value);
 owner?.push(()=>{subscriptions.delete(id);send({kind:'unsubscribe',id});});
 effect(()=>{send({kind:'subscribe',id,method:kind,args:reading(query)});value.value={...value.peek(),loading:true};});
 return value;
}
export function calculate(expression:string,values:any={}) {return request('calculate',{expression,values});}
export function __initialize(state:any) {if(initialized)throw Error('Runtime already initialized');initialized=true;draft=state.draft||{};revision=state.revision||0;}
export function __receive(messages:any[]) {
 batch(()=>{for(const message of messages){
  if(message.kind==='event') {
   if(!nodes.has(message.node)||nodes.get(message.node)!.mountID!==message.mountID)continue;
   edits.set(message.node,message.editRevision||0);
   const bound=handlers.get(message.node+':bind');if(bound && message.event==='change')bound(message);
   const handler=handlers.get(message.node+':'+message.handler);if(handler)handler(message);
  } else if(message.kind==='result') {
   const pending=requests.get(message.id);if(!pending)continue;requests.delete(message.id);
   if(message.error)pending.reject(Error(message.error));else pending.resolve(message.value);
  } else if(message.kind==='subscription') {
   const value=subscriptions.get(message.id);if(!value)continue;
   revision=Math.max(revision,message.value?.revision||0);
   value.value=message.error?{...value.peek(),loading:false,error:message.error}:{...message.value,loading:false,error:null};
  } else if(message.kind==='revision') revision=message.revision;
 }});
}
export function __flush() {
 const result={version:1,root,patches:[...patches.values()],messages:outbox};patches.clear();outbox=[];return result;
}
