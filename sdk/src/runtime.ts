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
type ActionInput = {type:'text'|'decimal'|'boolean'|'number'|'date'|'record';title?:string;required?:boolean;choices?:string[]};
type ActionDescription = {title:string;description?:string;inputs?:Record<string,ActionInput>;enabled?:boolean|Signal<boolean>|(()=>boolean)};
const actions = new Map<string,{description:ActionDescription;run:(args:any)=>Promise<any>}>();
const actionGeneration=signal(0);
function validDate(value:string):boolean {
 if(!/^\d{4}-\d{2}-\d{2}$/.test(value))return false;
 const [year,month,day]=value.split('-').map(Number);
 const leap=year%4===0&&(year%100!==0||year%400===0);
 return year>=1&&month>=1&&month<=12&&day>=1&&day<=[31,leap?29:28,31,30,31,30,31,31,30,31,30,31][month-1];
}
// A business action validates and writes one optimistic snapshot. Subscription
// refreshes may update presentation, but cannot bless its previously read values.
let actionSnapshot:{revision:number}|null=null;
/** One business operation shared by chat and optional visual controls. */
export function action(id:string,description:ActionDescription,handler:(args:any)=>any) {
 if(typeof id!=='string'||!/^[a-z][a-zA-Z0-9_.-]{0,63}$/.test(id))throw Error("Action IDs must start with a lowercase letter and contain 1..64 letters, digits, underscores, dots or hyphens, with no spaces. Use e.g. 'logTime' as the ID and 'Log time' as its title; ActionForm and tests use that same ID.");
 if(actions.has(id))throw Error('This action ID is already registered: '+id);
 if(actions.size>=64)throw Error('An app supports up to 64 named actions');
 if(!description?.title||typeof description.title!=='string'||description.title.length>256||typeof handler!=='function')throw Error("Sevra.action takes THREE arguments: action ID, {title,inputs}, then async inputs=>{...}. The handler is the third argument, not a field inside the description object.");
 const inputs=description.inputs===undefined?{}:description.inputs;
 if(!inputs||typeof inputs!=='object'||Array.isArray(inputs))throw Error('Action inputs must be an object of named input descriptions');
 if(Object.keys(inputs).length>32)throw Error('An action supports up to 32 inputs');
 for(const [key,input] of Object.entries(inputs)){
  if(!input||typeof input!=='object'||Array.isArray(input))throw Error('Action input '+key+' must be a description object');
  const unknown=Object.keys(input).filter(field=>!['type','title','required','choices'].includes(field));
  if(unknown.length)throw Error('Unsupported action input options for '+key+': '+unknown.join(', ')+'. Use only type, title, required and choices. Validate numeric bounds and other business rules inside the action handler; input metadata does not enforce min/max/step.');
  if(!/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/.test(key)||!['text','decimal','boolean','number','date','record'].includes(input.type)||(input.title!==undefined&&(typeof input.title!=='string'||input.title.length>256))||(input.required!==undefined&&typeof input.required!=='boolean')||(input.choices!==undefined&&(!Array.isArray(input.choices)||input.choices.length>200||input.choices.some(v=>typeof v!=='string'))))throw Error('Invalid action input: '+key);
 }
 for(const input of Object.values(inputs))if(input.choices&&(input.type==='number'||input.type==='boolean'))throw Error('String choices require a text, decimal, date or record input; number and boolean inputs use their own types');
 const run=async(args:any={})=>{
  if(!actionAvailable(description))throw Error('This action is currently unavailable');
  if(!args||typeof args!=='object'||Array.isArray(args)||Object.keys(args).some(key=>!Object.hasOwn(inputs,key)))throw Error('Use the declared action inputs');
  for(const [key,input] of Object.entries(inputs)){
   const value=args[key];
   if(value===undefined){if(input.required!==false)throw Error('Missing input: '+(input.title||key));continue;}
   if(input.type==='boolean'?typeof value!=='boolean':input.type==='number'?typeof value!=='number'||!Number.isFinite(value):typeof value!=='string')throw Error('Invalid input: '+(input.title||key)+'. Expected '+(input.type==='decimal'?'a JSON string containing a decimal, for example "3"':input.type==='boolean'?'a boolean':input.type==='number'?'a finite number':'a string'));
   if(input.required!==false&&(input.type==='text'||input.type==='record')&&!value.trim())throw Error('Missing input: '+(input.title||key));
   if(input.type==='decimal'&&(!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)$/.test(value)||!Number.isFinite(Number(value))))throw Error('Use a finite decimal for '+(input.title||key));
   if(input.type==='date'&&!validDate(value))throw Error('Use a valid YYYY-MM-DD date for '+(input.title||key));
   if(input.choices&&!input.choices.includes(value))throw Error('Choose a listed value for '+(input.title||key));
  }
  if(actionSnapshot)throw Error('Another business action is still running');
  const snapshot={revision};actionSnapshot=snapshot;
  try{return await handler(args);}finally{if(actionSnapshot===snapshot)actionSnapshot=null;}
 };
 const entry={description,run};actions.set(id,entry);
 actionGeneration.value=actionGeneration.peek()+1;
 owner?.push(()=>{if(actions.get(id)===entry){actions.delete(id);actionGeneration.value=actionGeneration.peek()+1;}});
 return run;
}
let outbox:any[] = [], requestID=0, mountID=0, root:string|null=null, initialized=false;
let draft:any={}, revision=0;
const reading=(value:any)=>value instanceof Signal ? value.value : typeof value==='function' ? value() : value;
function actionAvailable(description:ActionDescription):boolean {
 if(description.enabled===undefined)return true;
 const value=reading(description.enabled);
 if(typeof value!=='boolean')throw Error('Action enabled must be a synchronous boolean or boolean signal/function with no inputs. Omit enabled unless needed; validate input-dependent business rules inside the async handler.');
 return value;
}
const changed=(a:any,b:any)=>JSON.stringify(a)!==JSON.stringify(b);
function bounded() { if(nodes.size>512 || outbox.length>128 || requests.size>64) throw Error('App resource limit exceeded'); }
function send(message:any) {
 if(message.kind==='draft'){const existing=outbox.findIndex(m=>m.kind==='draft');if(existing>=0)outbox[existing]=message;else outbox.push(message);}
 else outbox.push(message);bounded();
}
function update(node:Node) { patches.set(node.id,{op:'put',node:{...node,props:{...node.props},children:[...node.children]}}); bounded(); }
export function h(type:any, props:any,...children:any[]):Descriptor { return {type,props:props||{},children:children.flat()}; }
function unknownAction(id:unknown):Error {
 const value=typeof id==='string'?JSON.stringify(id.slice(0,96)):'('+typeof id+')';
 const registered=actions.size?'Registered action IDs: '+[...actions.keys()].join(', ')+'.':'No actions are registered; call Sevra.action before mounting.';
 return Error('Unknown action ID '+value+'. '+registered+' Use the exact ID, not display titles or handler functions.');
}
/** Native controls for an existing named action; custom interfaces remain ordinary components. */
export function ActionForm(props:{action:string}):Descriptor {
 const entry=actions.get(props.action);if(!entry)throw unknownAction(props.action);
 const {description}=entry,busy=signal(false),status=signal('');
 const fields=Object.entries(description.inputs||{}).map(([id,input])=>({id,input,value:signal<any>(input.type==='boolean'?false:'')}));
 const available=()=>{actionGeneration.value;return actions.get(props.action)===entry&&!busy.value&&actionAvailable(description);};
 async function submit(){
  if(!available())return;
  busy.value=true;status.value='';
  try {
   const args:any={};
   for(const {id,input,value} of fields){
    const raw=value.peek();
    if(raw===''&&input.required===false)continue;
    if(input.type==='number'){
     if(typeof raw!=='string'||!raw.trim()||!Number.isFinite(Number(raw)))throw Error('Enter a number for '+(input.title||id));
     args[id]=Number(raw);
    }else args[id]=raw;
   }
   await entry.run(args);
   batch(()=>{for(const {input,value} of fields)value.value=input.type==='boolean'?false:'';status.value='Completed';});
  }catch(error:any){status.value=String(error?.message||error);}
  finally{busy.value=false;}
 }
 return h('column',{gap:12},
  h('text',{text:description.title,size:16,weight:'semibold'}),
  ...(description.description?[h('text',{text:description.description,color:'secondary'})]:[]),
  ...fields.map(({id,input,value})=>{
   const title=input.title||id,label=description.title+': '+title;
   if(input.type==='boolean')return h('toggle',{label,title,value,enabled:available});
   const control=input.choices
    ? h('picker',{label,value,options:['',...input.choices.filter(option=>option!=='')],enabled:available})
    : h('textField',{label,value,placeholder:input.type==='date'?'YYYY-MM-DD':'',enabled:available});
   return h('column',{gap:6},h('text',{text:title}),control);
  }),
  // Keep feedback above the submission point so a bottom-aligned form does not
  // append its validation error below the visible scroll area.
  h('text',{text:status,hidden:()=>status.value===''}),
  h('button',{title:description.title,onClick:submit,enabled:available}));
}
/** A conventional native workspace, composed only from the existing controls. */
export function Workspace(props:{sections:{title:string;table?:string;actions?:string[]}[]}):Descriptor {
 const sections=props.sections;
 if(!Array.isArray(sections)||!sections.length||sections.length>12)throw Error('Use 1 to 12 workspace sections');
 const titles=new Set<string>();
 for(const section of sections){
  if(!section||typeof section.title!=='string'||!section.title.trim()||section.title.length>256||titles.has(section.title))throw Error('Use distinct named workspace sections');
  titles.add(section.title);
  if(section.table!==undefined&&(typeof section.table!=='string'||!section.table))throw Error('Use a declared table alias');
  if(section.actions!==undefined){
   if(!Array.isArray(section.actions)||section.actions.length>16||section.actions.some(id=>typeof id!=='string'))throw Error('Workspace actions must be an array of up to 16 action ID strings, not display titles or handler functions');
   for(const id of section.actions)if(!actions.has(id))throw unknownAction(id);
  }
  if(!section.table&&!section.actions?.length)throw Error('A workspace section needs a table or action');
 }
 const children=sections.map(section=>{
  const search=signal('');
  return h('column',{gap:16},
   ...(section.table?[
    h('textField',{label:'Filter '+section.title,placeholder:'Filter '+section.title.toLowerCase(),value:search}),
    h('table',{table:section.table,label:section.title+' records',search})]:[]),
   ...(section.actions||[]).map(id=>h(ActionForm,{action:id})));
 });
 return h('tabs',{label:'Workspace sections',titles:sections.map(section=>section.title),value:signal(0)},...children);
}
export const Fragment='column';
export const Column='column', Row='row', Grid='grid', Split='split', Scroll='scroll', Section='section';
export const Text='text', Button='button', TextField='textField', TextEditor='textEditor', Toggle='toggle';
export const Picker='picker', Slider='slider', DatePicker='date', Progress='progress', Table='table';
export const Tabs='tabs', Disclosure='disclosure', Canvas='canvas', Image='image', Spacer='spacer';
const eventProps:Record<string,string[]>={button:['onClick'],textField:['onChange'],textEditor:['onChange'],toggle:['onChange'],picker:['onChange'],slider:['onChange'],date:['onChange'],tabs:['onChange'],disclosure:['onChange'],table:['onSelect','onActivate'],canvas:['onClick','onDrop']};
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
  if(key.startsWith('on')) {
   if(!eventProps[node.type]?.includes(key))throw Error('Unknown event '+key+' for '+node.type+'. Supported events: '+(eventProps[node.type]?.join(', ')||'none'));
   if(typeof value!=='function')throw Error('Event handlers must be functions');handlers.set(id+':'+key,value as any);continue;
  }
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
async function write(operations:any[],options:any={}) {
 if(!Array.isArray(operations))throw Error("data.transaction expects an array of operations, for example [{op:'insert',table:'alias',values:{column:'value'}}], not a single operation object");
 const snapshot=actionSnapshot,base=snapshot?.revision??revision;
 if(snapshot&&options.revision!==undefined&&options.revision!==base)throw Error('The action snapshot changed; retry the action');
 const result=await request('transaction',{operations,revision:options.revision??base,token:options.token||('op-'+Date.now()+'-'+Math.random()),...(options.undo?{undo:options.undo}:{})});
 revision=Math.max(revision,result.revision);
 if(snapshot&&actionSnapshot===snapshot)snapshot.revision=result.revision;
 return result;
}
export const data={
 page:(table:string,options:any={})=>request('page',{table,...options}),
 /** All rows for bounded business validation, with one stable read revision. */
 all:async(table:string)=>{
  const rows:any[]=[];let snapshot:number|undefined,total:number|undefined;
  while(true){
   const page=await request('page',{table,offset:rows.length,limit:200});
   if(!Array.isArray(page.rows)||!Number.isInteger(page.total)||page.total<0||page.total>20_000||!Number.isInteger(page.revision))throw Error('Table exceeds the complete-read limit or returned an invalid page');
   if(snapshot!==undefined&&(snapshot!==page.revision||total!==page.total))throw Error('The table changed while reading; retry the action');
   snapshot=page.revision;total=page.total;
   if(page.rows.length>200||rows.length+page.rows.length>page.total)throw Error('Invalid table page');
   rows.push(...page.rows);
   if(rows.length===page.total)return rows;
   if(!page.rows.length)throw Error('The table page is incomplete');
  }
 },
 query:(query:any)=>request('query',query),
 transaction:write,
 undo:async(receipt:any)=>{
  if(!receipt||typeof receipt.token!=='string'||!receipt.token)throw Error('data.undo requires the receipt returned by a successful transaction. Sevra already provides Undo last change outside the app; do not add a duplicate Undo button.');
  return write([],{undo:receipt.token,token:'undo-'+Date.now()+'-'+Math.random()});
 },
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
  if(message.kind==='command') {
   Promise.resolve().then(async()=>{
    if(message.action){const command=actions.get(message.action);if(!command)throw Error('Unknown app action');return await command.run(message.arguments||{});}
    const node=nodes.get(message.node);
    if(!node||node.mountID!==message.mountID)throw Error('This input changed; inspect the app again');
    let current:Node|undefined=node;
    while(current){if(current.props.enabled===false||current.props.hidden===true)throw Error('This input is currently unavailable');current=[...nodes.values()].find(parent=>parent.children.includes(current!.id));}
    if(!eventProps[node.type]?.includes(message.handler))throw Error('Unsupported input operation');
    const bound=handlers.get(node.id+':bind'),handler=handlers.get(node.id+':'+message.handler);
    if(!handler&&!(bound&&message.handler==='onChange'))throw Error('This control has no operation');
    edits.set(node.id,message.editRevision||0);
    if(bound&&message.handler==='onChange')bound(message);
    return await handler?.(message);
   }).then(value=>send({kind:'commandResult',id:message.id,value:value??null}),error=>send({kind:'commandResult',id:message.id,error:String(error?.message||error)}));
  } else if(message.kind==='event') {
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
 const declared=[...actions].map(([id,{description}])=>({id,title:description.title,description:description.description||'',inputPolicy:"Before invocation, match every required input to the user's supplied values. If any are missing, finish with a clarification question. Never send placeholders, invent values, or reuse another transaction's values without explicit instruction.",inputs:Object.fromEntries(Object.entries(description.inputs||{}).map(([key,input])=>[key,{...input,required:input.required!==false,valueType:input.type==='boolean'?'boolean':input.type==='number'?'number':'string'}])),enabled:actionAvailable(description)}));
 const interactions=[...nodes.values()].map(node=>({id:node.id,handlers:(eventProps[node.type]||[]).filter(key=>handlers.has(node.id+':'+key)||(key==='onChange'&&handlers.has(node.id+':bind')))})).filter(item=>item.handlers.length);
 const result={version:1,root,patches:[...patches.values()],messages:outbox,actions:declared,interactions};patches.clear();outbox=[];return result;
}
