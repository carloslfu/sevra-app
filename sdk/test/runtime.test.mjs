import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../../Sources/SevraAppRuntime/Resources/sdk.js',import.meta.url),'utf8');
function runtime(program){const context=vm.createContext({});vm.runInContext(source+';Sevra.__initialize({});'+program,context);return {run:code=>vm.runInContext(code,context),flush:()=>JSON.parse(vm.runInContext('JSON.stringify(Sevra.__flush())',context))};}
const settled=()=>new Promise(resolve=>setImmediate(resolve));
function receive(r,message){r.run('Sevra.__receive('+JSON.stringify([message])+');');}
test('workspace and forms identify unknown action IDs without accepting display titles or handlers',()=>{
 const r=runtime(`var logTime=Sevra.action('logTime',{title:'Log Time'},()=>{});Sevra.action('updateCost',{title:'Update Cost'},()=>{});`);
 for(const expression of ["Sevra.Workspace({sections:[{title:'Time',actions:['Log Time']}]})","Sevra.ActionForm({action:'Log Time'})"]){
  assert.throws(()=>r.run(expression),error=>/Unknown action ID "Log Time"/.test(error.message)&&/logTime, updateCost/.test(error.message)&&/not display titles or handler functions/.test(error.message));
 }
 assert.throws(()=>r.run("Sevra.Workspace({sections:[{title:'Time',actions:[logTime]}]})"),/array of up to 16 action ID strings/);
 assert.throws(()=>r.run("Sevra.ActionForm({action:logTime})"),/Unknown action ID \(function\)/);
 assert.throws(()=>r.run("Sevra.ActionForm({action:'x'.repeat(10000)})"),error=>error.message.length<400);
 r.run("Sevra.mount(Sevra.h(Sevra.Workspace,{sections:[{title:'Time',actions:['logTime']}]}));");
 assert.equal(r.flush().actions.length,2);
 const empty=runtime('');
 assert.throws(()=>empty.run("Sevra.ActionForm({action:'save'})"),/No actions are registered/);
});
test('action registration explains a misplaced handler and preserves the three-argument contract',async()=>{
 const r=runtime('');
 for(const description of ["undefined","null","{title:42}","{title:'Add',handler:()=>{}}"]){
  assert.throws(()=>r.run(`Sevra.action('add',${description});`),/THREE arguments/);
 }
 for(const id of ["'Log Time'","'LogTime'","''",'undefined','null',"'a'.repeat(65)"]){
  assert.throws(()=>r.run(`Sevra.action(${id},{title:'Log time'},()=>{});`),/start with a lowercase letter/);
 }
 r.run(`Sevra.action('add',{title:'Add'},()=>({saved:true}));`);
 assert.throws(()=>r.run(`Sevra.action('add',{title:'Another'},()=>{});`),/already registered: add/);
 receive(r,{kind:'command',id:'valid',action:'add',arguments:{}});await settled();
 assert.equal(r.flush().messages.find(m=>m.id==='valid').value.saved,true);
});
test('action input metadata refuses silently ignored validation options and malformed contracts',async()=>{
 const r=runtime('var saved=[];');
 for(const option of ['min:0','max:10','step:1','default:2']){
  assert.throws(()=>r.run(`Sevra.action('pay',{title:'Pay',inputs:{amount:{type:'decimal',${option}}}},a=>saved.push(a.amount));`),/Unsupported action input options.*inside the action handler/);
 }
 for(const inputs of ['null','false','[]',"'amount'"]){
  assert.throws(()=>r.run(`Sevra.action('pay',{title:'Pay',inputs:${inputs}},()=>{});`),/object of named input descriptions/);
 }
 for(const input of ['null','[]',"{type:'decimal',required:'false'}","{type:'decimal',title:2}","{type:'decimal',choices:null}"]){
  assert.throws(()=>r.run(`Sevra.action('pay',{title:'Pay',inputs:{amount:${input}}},()=>{});`),/action input|Action input/);
 }
 r.run(`Sevra.action('pay',{title:'Pay',inputs:{amount:{type:'decimal',title:'Amount',required:true}}},a=>{if(Number(a.amount)<=0)throw Error('Amount must be positive');saved.push(a.amount);});`);
 receive(r,{kind:'command',id:'invalid',action:'pay',arguments:{amount:'0'}});await settled();
 assert.match(r.flush().messages.find(m=>m.id==='invalid').error,/positive/);assert.equal(r.run('saved.length'),0);
 receive(r,{kind:'command',id:'valid',action:'pay',arguments:{amount:'2.25'}});await settled();
 assert.equal(r.flush().messages.find(m=>m.id==='valid').error,undefined);assert.equal(r.run('saved[0]'),'2.25');
});
test('decimal inputs reject numeric overflow before the handler without rounding valid strings',async()=>{
 const r=runtime(`var saved=[];Sevra.action('pay',{title:'Pay',inputs:{amount:{type:'decimal'}}},args=>saved.push(args.amount));`);
 for(const amount of ['9'.repeat(400),'-'+'9'.repeat(400),'Infinity','1e400']){
  receive(r,{kind:'command',id:'invalid',action:'pay',arguments:{amount}});await settled();
  assert.match(r.flush().messages.find(m=>m.id==='invalid').error,/finite decimal/);
 }
 assert.equal(r.run('saved.length'),0);
 for(const amount of ['0','-0.50','9007199254740993.25']){
  receive(r,{kind:'command',id:'valid',action:'pay',arguments:{amount}});await settled();
  assert.equal(r.flush().messages.find(m=>m.id==='valid').error,undefined);
  assert.equal(r.run('saved[saved.length-1]'),amount);
 }
});
test('action availability rejects async and nonboolean predicates before any handler runs',async()=>{
 for(const enabled of ['async()=>false',"()=> 'false'",'1','null']){
  const r=runtime(`var saved=0,failure='';var run=Sevra.action('apply',{title:'Apply',enabled:${enabled}},()=>++saved);run().catch(error=>failure=error.message);`);
  await settled();
  assert.equal(r.run('saved'),0);assert.match(r.run('failure'),/synchronous boolean/);
  assert.throws(()=>r.flush(),/synchronous boolean/);
 }
 const r=runtime(`var enabled=Sevra.signal(false),saved=0,failure='';var run=Sevra.action('apply',{title:'Apply',enabled:()=>enabled.value},()=>++saved);Sevra.mount(Sevra.h(Sevra.ActionForm,{action:'apply'}));run().catch(error=>failure=error.message);`);
 await settled();assert.equal(r.run('saved'),0);assert.match(r.run('failure'),/currently unavailable/);
 assert.equal(r.flush().actions[0].enabled,false);
 r.run('enabled.value=true;run();');await settled();assert.equal(r.run('saved'),1);
 assert.equal(r.flush().actions[0].enabled,true);
});
test('string choices reject incompatible input types and share validation between forms and named actions',async()=>{
 const r=runtime('var saved=[];');
 for(const type of ['number','boolean'])assert.throws(()=>r.run(`Sevra.action('choose',{title:'Choose',inputs:{value:{type:'${type}',choices:['1','2']}}},args=>saved.push(args.value));`),/String choices require/);
 r.run(`Sevra.action('choose',{title:'Choose',inputs:{value:{type:'text',title:'Value',choices:['One','Two']}}},args=>saved.push(args.value));Sevra.mount(Sevra.h(Sevra.ActionForm,{action:'choose'}));`);
 const nodes=r.flush().patches.map(p=>p.node),picker=nodes.find(n=>n?.type==='picker'),button=nodes.find(n=>n?.type==='button');
 assert.deepEqual(picker.props.options,['','One','Two']);
 receive(r,{kind:'command',id:'invalid',action:'choose',arguments:{value:'Three'}});await settled();
 assert.match(r.flush().messages.find(m=>m.id==='invalid').error,/Choose a listed value/);assert.equal(r.run('saved.length'),0);
 receive(r,{kind:'command',id:'select',node:picker.id,mountID:picker.mountID,handler:'onChange',value:'Two'});await settled();r.flush();
 receive(r,{kind:'command',id:'submit',node:button.id,mountID:button.mountID,handler:'onClick'});await settled();
 assert.equal(r.run('saved[0]'),'Two');assert(r.flush().patches.some(p=>p.node?.props.text==='Completed'));
});
test('transaction shape errors identify the array contract before sending a write',async()=>{
 const r=runtime(`var failure='';Sevra.data.transaction({op:'insert',table:'t',values:{n:'1'}}).catch(error=>failure=error.message);`);
 await settled();assert.match(r.run('failure'),/expects an array of operations/);assert.equal(r.flush().messages.length,0);
 r.run(`Sevra.data.transaction([{op:'insert',table:'t',values:{n:'1'}}]);`);
 assert.equal(r.flush().messages.find(m=>m.method==='transaction').args.operations[0].values.n,'1');
});
test('named date inputs reject impossible calendar dates before invoking the business handler',async()=>{
 const r=runtime(`var saved=[];Sevra.action('book',{title:'Book',inputs:{date:{type:'date'}}},args=>saved.push(args.date));`);
 for(const date of ['2026-02-29','1900-02-29','2026-04-31','2026-00-12','0000-01-01']){
  receive(r,{kind:'command',id:date,action:'book',arguments:{date}});await settled();
  assert.match(r.flush().messages.find(m=>m.id===date).error,/valid YYYY-MM-DD/);
 }
 assert.equal(r.run('saved.length'),0);
 for(const date of ['2000-02-29','2028-02-29','0001-01-01','9999-12-31']){
  receive(r,{kind:'command',id:date,action:'book',arguments:{date}});await settled();
  assert.equal(r.flush().messages.find(m=>m.id===date).error,undefined);
 }
 assert.equal(r.run('saved.length'),4);
});
test('required text and record inputs reject blanks while optional text and literal values are preserved',async()=>{
 const r=runtime(`var saved=[];Sevra.action('save',{title:'Save',inputs:{reference:{type:'text'},key:{type:'record'},note:{type:'text',required:false}}},args=>saved.push(args));`);
 for(const field of ['reference','key'])for(const value of ['', '   ', '\t\n', ' \t\n\u00A0\uFEFF']){
  receive(r,{kind:'command',id:'invalid',action:'save',arguments:{reference:'R1',key:'K1',[field]:value}});await settled();
  assert.match(r.flush().messages.find(m=>m.id==='invalid').error,/Missing input/);
 }
 assert.equal(r.run('saved.length'),0);
 for(const note of ['', '   ']){
  receive(r,{kind:'command',id:'valid',action:'save',arguments:{reference:' R1 ',key:'K1',note}});await settled();
  assert.equal(r.flush().messages.find(m=>m.id==='valid').error,undefined);
 }
 assert.equal(r.run('saved[0].reference'),' R1 ');assert.equal(r.run('saved[0].note'),'');assert.equal(r.run('saved[1].note'),'   ');
 receive(r,{kind:'command',id:'unicode',action:'save',arguments:{reference:'\u0085',key:'\u0085'}});await settled();
 assert.equal(r.flush().messages.find(m=>m.id==='unicode').error,undefined);
 assert.equal(r.run('saved[2].reference'),'\u0085');
});
test('complete business reads traverse pages and refuse mixed revisions, truncation and excess rows',async()=>{
 async function start(){const r=runtime(`var answer=null;Sevra.data.all('ledger').then(rows=>answer={rows},error=>answer={error:error.message});`);return r;}
 async function page(r,value){const call=r.flush().messages.find(m=>m.method==='page');assert(call);receive(r,{kind:'result',id:call.id,value});await settled();return call;}
 const r=await start(),first=Array.from({length:200},(_,i)=>({id:String(i)}));
 assert.equal((await page(r,{rows:first,total:201,revision:4})).args.offset,0);
 assert.equal((await page(r,{rows:[{id:'last'}],total:201,revision:4})).args.offset,200);
 assert.equal(r.run('answer.rows.length'),201);assert.equal(r.run('answer.rows[200].id'),'last');
 for(const value of [{rows:[],total:1,revision:4},{rows:[],total:20_001,revision:4},{rows:[{}],total:0,revision:4}]){
  const bad=await start();await page(bad,value);assert(bad.run('answer.error'));
 }
 const mixed=await start();await page(mixed,{rows:first,total:201,revision:4});await page(mixed,{rows:[{}],total:201,revision:5});assert.match(mixed.run('answer.error'),/changed while reading/);
 const empty=await start();await page(empty,{rows:[],total:0,revision:4});assert.equal(empty.run('answer.rows.length'),0);
});
test('native action forms share the named operation, retain failed drafts and clear only successful drafts',async()=>{
 const r=runtime(`var saved=[],fail=true;Sevra.action('save',{title:'Save entry',inputs:{reference:{type:'text',title:'Reference'},amount:{type:'decimal',title:'Amount'}}},async args=>{await Sevra.data.page('t');if(fail)throw Error('Cannot save this entry');saved.push(args);return args;});Sevra.mount(Sevra.h(Sevra.ActionForm,{action:'save'}));`);
 const frame=r.flush(),nodes=frame.patches.map(p=>p.node),reference=nodes.find(n=>n?.props.label==='Save entry: Reference'),amount=nodes.find(n=>n?.props.label==='Save entry: Amount'),button=nodes.find(n=>n?.type==='button');
 async function input(node,value){receive(r,{kind:'command',id:'input',node:node.id,mountID:node.mountID,handler:'onChange',value});await settled();r.flush();}
 await input(reference,'R1');await input(amount,'12.50');
 async function submit(){receive(r,{kind:'command',id:'submit',node:button.id,mountID:button.mountID,handler:'onClick'});await settled();return r.flush();}
 let pending=await submit();assert.equal(pending.patches.find(p=>p.node?.id===button.id).node.props.enabled,false);
 let page=pending.messages.find(m=>m.method==='page');receive(r,{kind:'result',id:page.id,value:{revision:0,rows:[]}});await settled();
 let failed=r.flush();assert(failed.patches.some(p=>p.node?.props.text==='Cannot save this entry'));
 assert.equal(r.run('saved.length'),0);
 assert.equal(failed.patches.find(p=>p.node?.id===amount.id).node.props.value,'12.50');
 r.run('fail=false');pending=await submit();page=pending.messages.find(m=>m.method==='page');receive(r,{kind:'result',id:page.id,value:{revision:0,rows:[]}});await settled();
 const success=r.flush();assert(success.patches.some(p=>p.node?.props.text==='Completed'));
 assert.equal(r.run('saved[0].amount'),'12.50');assert.equal(success.patches.find(p=>p.node?.id===amount.id).node.props.value,'');
 receive(r,{kind:'command',id:'chat',action:'save',arguments:{reference:'R2',amount:'0'}});await settled();page=r.flush().messages.find(m=>m.method==='page');receive(r,{kind:'result',id:page.id,value:{revision:0,rows:[]}});await settled();
 assert.equal(r.flush().messages.find(m=>m.id==='chat').value.reference,'R2');assert.equal(r.run('saved.length'),2);
});
test('action forms do not invent a zero for missing numbers and keep action-qualified input labels',async()=>{
 const r=runtime(`var saved=null;Sevra.action('apply',{title:'Apply',inputs:{count:{type:'number',title:'Count'},note:{type:'text',title:'Note',required:false}}},args=>{saved=args;});Sevra.mount(Sevra.h(Sevra.ActionForm,{action:'apply'}));`);
 const nodes=r.flush().patches.map(p=>p.node),button=nodes.find(n=>n?.type==='button'),field=nodes.find(n=>n?.props.label==='Apply: Count');
 receive(r,{kind:'command',id:'missing',node:button.id,mountID:button.mountID,handler:'onClick'});await settled();
 assert(r.flush().patches.some(p=>p.node?.props.text==='Enter a number for Count'));assert.equal(r.run('saved'),null);
 receive(r,{kind:'command',id:'input',node:field.id,mountID:field.mountID,handler:'onChange',value:'0'});await settled();r.flush();
 receive(r,{kind:'command',id:'zero',node:button.id,mountID:button.mountID,handler:'onClick'});await settled();r.flush();
 assert.equal(r.run('saved.count'),0);assert.equal(r.run('Object.hasOwn(saved,"note")'),false);
});
test('a form cannot retain executable access to an unmounted action',async()=>{
 const r=runtime(`var shown=Sevra.signal(true),calls=0;function Register(){Sevra.action('apply',{title:'Apply'},()=>++calls);return Sevra.h(Sevra.Text,{text:'Available'});}Sevra.mount(Sevra.h(Sevra.Column,{},()=>shown.value?Sevra.h(Register,{key:'registration'}):null,Sevra.h(Sevra.ActionForm,{key:'form',action:'apply'})));`);
 const button=r.flush().patches.find(p=>p.node?.type==='button').node;
 r.run('shown.value=false');const removed=r.flush();
 assert.equal(removed.actions.length,0);assert.equal(removed.patches.find(p=>p.node?.id===button.id).node.props.enabled,false);
 receive(r,{kind:'command',id:'old',node:button.id,mountID:button.mountID,handler:'onClick'});await settled();
 assert.match(r.flush().messages.find(m=>m.id==='old').error,/unavailable/);assert.equal(r.run('calls'),0);
});
test('named action writes retain their snapshot across live refreshes and reject overlapping actions',async()=>{
 const r=runtime(`Sevra.liveQuery({table:'stock'});Sevra.action('ship',{title:'Ship'},async()=>{await Sevra.data.page('stock');return await Sevra.data.transaction([{op:'insert',table:'stock',values:{quantity:'-1'}}]);});Sevra.mount(Sevra.h(Sevra.Text,{text:'Stock'}));`);
 const subscription=r.flush().messages.find(m=>m.kind==='subscribe');
 r.run(`Sevra.__receive([{kind:'command',id:'first',action:'ship'}]);`);
 await new Promise(resolve=>setImmediate(resolve));
 const page=r.flush().messages.find(m=>m.method==='page');
 r.run('Sevra.__receive('+JSON.stringify([
  {kind:'command',id:'overlap',action:'ship'},
  {kind:'subscription',id:subscription.id,value:{revision:2,rows:[],total:0}},
  {kind:'result',id:page.id,value:{revision:0,rows:[],total:0}}
 ])+');');
 await new Promise(resolve=>setImmediate(resolve));
 let frame=r.flush();
 assert.match(frame.messages.find(m=>m.id==='overlap').error,/still running/);
 const write=frame.messages.find(m=>m.method==='transaction');
 assert.equal(write.args.revision,0,'a subscription must not advance the action snapshot');
 r.run('Sevra.__receive('+JSON.stringify([{kind:'result',id:write.id,error:'Stale revision'}])+');');
 await new Promise(resolve=>setImmediate(resolve));
 assert.match(r.flush().messages.find(m=>m.id==='first').error,/Stale/);
 r.run(`Sevra.__receive([{kind:'command',id:'retry',action:'ship'}]);`);
 await new Promise(resolve=>setImmediate(resolve));
 const retryPage=r.flush().messages.find(m=>m.method==='page');
 r.run('Sevra.__receive('+JSON.stringify([{kind:'result',id:retryPage.id,value:{revision:2,rows:[],total:0}}])+');');
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(r.flush().messages.find(m=>m.method==='transaction').args.revision,2);
});
test('Undo without a transaction receipt refuses before requesting a write',async()=>{
 const r=runtime(`Sevra.mount(Sevra.h(Sevra.Text,{text:'Test'}));`);
 r.flush();
 for(const input of ['undefined','null','{}',`{token:''}`,`{token:42}`]) {
  await assert.rejects(r.run(`Sevra.data.undo(${input})`),/requires the receipt.*already provides Undo/);
  assert.equal(r.flush().messages.length,0);
 }
});
test('own committed writes and Undo advance the action fence while external revisions do not',async()=>{
 const r=runtime(`Sevra.action('change',{title:'Change'},async()=>{const receipt=await Sevra.data.transaction([{op:'insert',table:'t',values:{n:'1'}}]);return await Sevra.data.undo(receipt);});Sevra.mount(Sevra.h(Sevra.Text,{text:'Test'}));`);
 r.flush();r.run(`Sevra.__receive([{kind:'command',id:'change',action:'change'}]);`);
 await new Promise(resolve=>setImmediate(resolve));
 const first=r.flush().messages.find(m=>m.method==='transaction');
 assert.equal(first.args.revision,0);
 r.run('Sevra.__receive('+JSON.stringify([{kind:'revision',revision:2},{kind:'result',id:first.id,value:{revision:1,token:'saved'}}])+');');
 await new Promise(resolve=>setImmediate(resolve));
 const undo=r.flush().messages.find(m=>m.method==='transaction');
 assert.equal(undo.args.revision,1);assert.equal(undo.args.undo,'saved');
});
test('an earlier outside write cannot advance a later action snapshot',async()=>{
 const r=runtime(`Sevra.action('change',{title:'Change'},async()=>{await Sevra.data.page('t');return await Sevra.data.transaction([{op:'insert',table:'t',values:{n:'2'}}]);});Sevra.mount(Sevra.h(Sevra.Text,{text:'Test'}));Sevra.data.transaction([{op:'insert',table:'t',values:{n:'1'}}]);`);
 const outside=r.flush().messages.find(m=>m.method==='transaction');
 r.run(`Sevra.__receive([{kind:'command',id:'change',action:'change'}]);`);
 await new Promise(resolve=>setImmediate(resolve));
 const page=r.flush().messages.find(m=>m.method==='page');
 r.run('Sevra.__receive('+JSON.stringify([{kind:'result',id:outside.id,value:{revision:1,token:'outside'}},{kind:'result',id:page.id,value:{revision:0,rows:[]}}])+');');
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(r.flush().messages.find(m=>m.method==='transaction').args.revision,0);
});
test('named actions share validation and outcomes between chat and the visual handler',async()=>{
 const r=runtime(`var total=Sevra.signal('0');var add=Sevra.action('add',{title:'Add amount',inputs:{amount:{type:'decimal',title:'Amount'}}},async({amount})=>{total.value=amount;return {saved:amount};});Sevra.mount(Sevra.h(Sevra.Text,{text:total}));`);
 assert.equal(r.flush().actions[0].inputs.amount.type,'decimal');
 r.run(`Sevra.__receive([{kind:'command',id:'one',action:'add',arguments:{amount:'12.50'}}]);`);
 await new Promise(resolve=>setImmediate(resolve));
 const result=r.flush();
 assert.equal(result.messages.find(m=>m.kind==='commandResult').value.saved,'12.50');
 assert.equal(r.run('total.value'),'12.50');
 r.run(`Sevra.__receive([{kind:'command',id:'two',action:'add',arguments:{amount:'12bad'}}]);`);
 await new Promise(resolve=>setImmediate(resolve));
 assert.match(r.flush().messages[0].error,/decimal/);
 assert.equal(r.run('total.value'),'12.50');
 await r.run(`add({amount:'8'})`);
 assert.equal(r.run('total.value'),'8');
});
test('component actions are removed with their scope and can be remounted',async()=>{
 const r=runtime(`var shown=Sevra.signal(true),calls=0;function Panel(){Sevra.action('apply',{title:'Apply',inputs:{}},()=>++calls);return Sevra.h(Sevra.Text,{text:'Panel'});}Sevra.mount(Sevra.h(Sevra.Column,{},()=>shown.value?Sevra.h(Panel,{}):null));`);
 assert.equal(r.flush().actions.length,1);
 r.run('shown.value=false');assert.equal(r.flush().actions.length,0);
 r.run('shown.value=true');assert.equal(r.flush().actions.length,1);
 r.run(`Sevra.__receive([{kind:'command',id:'apply',action:'apply',arguments:{}}]);`);
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(r.flush().messages.find(m=>m.kind==='commandResult').value,1);
});
test('conversation controls reject stale mounts, disabled containers and unknown handlers',async()=>{
 const r=runtime(`var value=Sevra.signal(''),enabled=Sevra.signal(false);Sevra.mount(Sevra.h(Sevra.Column,{enabled},Sevra.h(Sevra.TextField,{label:'Name',value})));`);
 const frame=r.flush(),field=frame.patches.find(p=>p.node?.type==='textField').node;
 async function command(extra){r.run('Sevra.__receive('+JSON.stringify([{kind:'command',id:'input',node:field.id,mountID:field.mountID,handler:'onChange',value:'Updated',...extra}])+');');await new Promise(resolve=>setImmediate(resolve));return r.flush().messages.find(m=>m.kind==='commandResult');}
 assert.match((await command({})).error,/unavailable/);
 r.run('enabled.value=true');r.flush();
 assert.match((await command({mountID:9999})).error,/changed/);
 assert.match((await command({handler:'onClick'})).error,/Unsupported/);
 assert.equal(r.run('value.value'),'');
 assert.equal((await command({})).error,undefined);
 assert.equal(r.run('value.value'),'Updated');
});
test('unsupported native event handlers fail instead of silently losing interactions',()=>{
 assert.throws(()=>runtime(`Sevra.mount(Sevra.h(Sevra.TextField,{onValueChange:()=>{}}));`),/Unknown event onValueChange for textField.*onChange/);
 assert.throws(()=>runtime(`Sevra.mount(Sevra.h(Sevra.Text,{text:'Click',onClick:()=>{}}));`),/Unknown event onClick for text/);
 assert.throws(()=>runtime(`Sevra.mount(Sevra.h(Sevra.Button,{onClick:'save'}));`),/Event handlers must be functions/);
 const r=runtime(`var value=Sevra.signal(''),seen='';Sevra.mount(Sevra.h(Sevra.TextField,{value,onChange:e=>{seen=value.value+':'+e.value;}}));`);
 r.flush();r.run(`Sevra.__receive([{kind:'event',node:'root',mountID:1,event:'change',handler:'onChange',value:'typed'}]);`);
 assert.equal(r.run('seen'),'typed:typed');
});
test('a keyed row retains its private state when data reorders, and removed rows stop reacting',()=>{
 const r=runtime(`var rows=Sevra.signal([{id:'a',name:'First'},{id:'b',name:'Second'}]);var calls=0;
 function Item(row){calls++;let count=Sevra.signal(0);return Sevra.h(Sevra.Button,{title:()=>row.value.name+':'+count.value,onClick:()=>count.value++});}
 Sevra.mount(Sevra.h(Sevra.For,{each:rows,by:x=>x.id},Item));`);
 r.flush();r.run(`Sevra.__receive([{kind:'event',node:'root/a',mountID:2,handler:'onClick'}]);rows.value=[{id:'b',name:'Second'},{id:'a',name:'Renamed'}];`);
 let frame=r.flush();assert.equal(r.run('calls'),2);assert.ok(frame.patches.some(p=>p.node?.id==='root/a'&&p.node.props.title==='Renamed:1'));
 r.run(`rows.value=[{id:'b',name:'Second'}]`);frame=r.flush();assert.ok(frame.patches.some(p=>p.op==='remove'&&p.id==='root/a'));
 r.run(`Sevra.__receive([{kind:'event',node:'root/a',mountID:2,handler:'onClick'}])`);assert.equal(r.flush().patches.length,0);
});
test('conditional content at the same position actually changes native type and value',()=>{
 const r=runtime(`var yes=Sevra.signal(true);Sevra.mount(Sevra.h(Sevra.Column,{},()=>yes.value?Sevra.h(Sevra.Text,{text:'Yes'}):Sevra.h(Sevra.Button,{title:'No'})));`);
 r.flush();r.run('yes.value=false');assert.ok(r.flush().patches.some(p=>p.node?.type==='button'&&p.node.props.title==='No'));
});
test('native text acknowledgements carry edit revisions and draft ownership',()=>{
 const r=runtime(`var text=Sevra.draftSignal('title','');Sevra.mount(Sevra.h(Sevra.TextField,{value:text}));`);
 assert.equal(r.flush().patches[0].node.props.draftKey,'title');
 r.run(`Sevra.__receive([{kind:'event',node:'root',mountID:1,event:'change',handler:'onChange',value:'Newest',editRevision:8}]);`);
 const node=r.flush().patches[0].node;assert.equal(node.props.value,'Newest');assert.equal(node.props.editRevision,8);
});
test('dependent computed values are batched into one patch per node',()=>{
 const r=runtime(`var a=Sevra.signal(1),b=Sevra.signal(2),sum=Sevra.computed(()=>a.value+b.value);Sevra.mount(Sevra.h(Sevra.Text,{text:()=>String(sum.value)}));`);
 r.flush();r.run('Sevra.batch(()=>{a.value=4;b.value=5;})');const frame=r.flush();assert.equal(frame.patches.length,1);assert.equal(frame.patches[0].node.props.text,'9');
});
test('unmount releases a component query subscription and its effects',()=>{
 const r=runtime(`var visible=Sevra.signal(true),tick=Sevra.signal(0),seen=0;
 function Child(){Sevra.liveQuery({table:'items'});Sevra.effect(()=>{seen=tick.value;});return Sevra.h(Sevra.Text,{text:'child'});}
 Sevra.mount(Sevra.h(Sevra.Column,{},()=>visible.value?Sevra.h(Child,{}):null));`);
 assert.ok(r.flush().messages.some(m=>m.kind==='subscribe'));r.run('visible.value=false');assert.ok(r.flush().messages.some(m=>m.kind==='unsubscribe'));
 r.run('tick.value=7');assert.equal(r.run('seen'),0);
});

test('replaced controls have new mount identities and refuse queued events for the old control',()=>{
 const r=runtime(`var second=Sevra.signal(false), clicks=0;Sevra.mount(Sevra.h(Sevra.Column,{},()=>Sevra.h(Sevra.Button,{title:second.value?'Second':'First',onClick:()=>clicks++})));`);
 const before=r.flush().patches.find(p=>p.node?.id==='root/0').node;
 r.run('second.value=true');
 const after=r.flush().patches.find(p=>p.node?.id==='root/0').node;
 assert.notEqual(before.mountID,after.mountID);
 r.run(`Sevra.__receive([{kind:'event',node:'root/0',mountID:${before.mountID},handler:'onClick'}])`);
 assert.equal(r.run('clicks'),0);
 r.run(`Sevra.__receive([{kind:'event',node:'root/0',mountID:${after.mountID},handler:'onClick'}])`);
 assert.equal(r.run('clicks'),1);
});
