import {Column,Row,Text,TextField,Button,Picker,Table,signal,draftSignal,data,mount,liveQuery,For,action} from '@sevra/sdk';
function Jobs() {
 const title=draftSignal('title',''), owner=draftSignal('owner',''), stage=signal('Todo'), selected=signal<any>(null), status=signal(''), busy=signal(false);
 const jobs=liveQuery({sources:[{table:'jobs'}],select:[{id:'stage',column:{source:0,column:'stage'}},{id:'count',aggregate:'countRows'}],groupBy:[{source:0,column:'stage'}],limit:20},'query');
 const saveJob=action('saveJob',{title:'Add or update a job',inputs:{title:{type:'text',title:'Job title'},owner:{type:'text',title:'Owner'},stage:{type:'text',title:'Stage',choices:['Todo','Doing','Done']},rowID:{type:'record',title:'Existing job',required:false}}},async({title,owner,stage,rowID})=>{
  if(!title.trim())throw Error('Enter a job title.');
  const receipt=await data.transaction([{op:rowID?'update':'insert',table:'jobs',...(rowID?{id:rowID}:{}),values:{title,owner,stage}}]);status.value='Job saved.';return receipt;
 });
 action('removeJob',{title:'Remove a job',inputs:{rowID:{type:'record',title:'Job'}}},async({rowID})=>{
  const receipt=await data.transaction([{op:'delete',table:'jobs',id:rowID}]);status.value='Job removed.';return receipt;
 });
 async function save() {
  if(busy.value)return;
  if(!title.value.trim()){status.value='Enter a job title.';return;}
  busy.value=true;
  const row=selected.value, values={title:title.value,owner:owner.value,stage:stage.value};
  try {
   const receipt=await saveJob({...values,...(row?{rowID:row.id}:{})});
   if(title.value===values.title&&owner.value===values.owner&&stage.value===values.stage&&selected.value===row){selected.value=null;title.value='';owner.value='';}
   else if(row&&selected.value===row)selected.value={...row,id:receipt.results[0].id};
   status.value='Job saved.';
  }catch(error){status.value=error.message;}finally{busy.value=false;}
 }
 return <Column gap={16}>
  <Text text="Work in progress" size={26} weight="bold"/>
  <Column gap={8}>
   <Row gap={12} alignment="bottom">
    <Column width={220} gap={4}><Text text="Job" size={11} color="secondary"/><TextField label="Job title" placeholder="Job title" value={title}/></Column>
    <Column width={160} gap={4}><Text text="Owner" size={11} color="secondary"/><TextField label="Owner" placeholder="Owner" value={owner}/></Column>
   </Row>
   <Row gap={12} alignment="bottom"><Column gap={4}><Text text="Stage" size={11} color="secondary"/><Picker label="Stage" options={['Todo','Doing','Done']} value={stage}/></Column><Button title="Save job" enabled={()=>!busy.value} onClick={save}/><Button title="New job" onClick={()=>{selected.value=null;title.value='';owner.value='';stage.value='Todo';status.value='';}}/></Row>
   <Text text={status} hidden={()=>!status.value}/>
  </Column>
  <For each={()=>['Todo','Doing','Done']} by={x=>x} layout={Row} gap={24}>{item=><Column width={100} gap={4}><Text text={item} color="secondary" size={11}/><Text text={()=>String(jobs.value.rows.find(row=>row.values.stage===item.value)?.values.count||0)} size={20}/></Column>}</For>
  <Table selection={()=>selected.value?.key||''} table="jobs" label="Jobs" height={300} onSelect={event=>{selected.value=event.value;title.value=event.value.values.title;owner.value=event.value.values.owner||'';stage.value=event.value.values.stage;status.value='';}}/>
 </Column>;
}
mount(Jobs);
