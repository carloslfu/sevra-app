import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../../Sources/SevraAppRuntime/Resources/sdk.js',import.meta.url),'utf8');
function runtime(program){const context=vm.createContext({});vm.runInContext(source+';Sevra.__initialize({});'+program,context);return {run:code=>vm.runInContext(code,context),flush:()=>JSON.parse(vm.runInContext('JSON.stringify(Sevra.__flush())',context))};}
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
