import {Column,Row,Text,TextField,Button,Table,signal,draftSignal,liveQuery,data,mount} from '@sevra/sdk';
function Inventory() {
 const name=draftSignal('name',''), quantity=draftSignal('quantity','0'), search=signal('');
 const selected=signal<any>(null), status=signal(''), busy=signal(false);
 const stock=liveQuery(()=>({table:'stock',search:search.value,limit:20}));
 async function save() {
  if(busy.value)return;
  if(!name.value.trim()){status.value='Enter an item name.';return;}
  busy.value=true;
  const row=selected.value, submitted={name:name.value,quantity:quantity.value};
  try {
   const receipt=await data.transaction([{op:row?'update':'insert',table:'stock',...(row?{id:row.id}:{}),values:submitted}]);
   if(name.value===submitted.name && quantity.value===submitted.quantity && selected.value===row){name.value='';quantity.value='0';selected.value=null;}
   else if(row && selected.value===row)selected.value={...row,id:receipt.results[0].id};
   status.value='Saved to your workbook.';
  } catch(error) {status.value=String(error.message);} finally {busy.value=false;}
 }
 return <Column gap={16}>
  <Column gap={4}><Text text="Stock room" size={26} weight="bold"/><Text color="secondary" text={()=>stock.value.loading?'Updating…':`${stock.value.total||0} ${search.value.trim()?'matching ':''}${(stock.value.total||0)===1?'item':'items'}${search.value.trim()?'':' in stock'}`}/></Column>
  <Column gap={8}>
   <Row gap={12} alignment="bottom">
    <Column gap={4} width={230}><Text text="Item" size={11} color="secondary"/><TextField label="Item name" placeholder="Item name" value={name}/></Column>
    <Column gap={4} width={100}><Text text="Quantity" size={11} color="secondary"/><TextField label="Quantity" value={quantity}/></Column>
   </Row>
   <Row gap={8}><Button title={()=>selected.value?'Save changes':'Add item'} enabled={()=>!busy.value} onClick={save}/><Button title="New item" onClick={()=>{selected.value=null;name.value='';quantity.value='0';status.value='';}}/></Row>
   <Text text={status} label="Save status" hidden={()=>!status.value}/>
  </Column>
  <Column gap={8}>
   <TextField label="Search stock" placeholder="Search stock" value={search}/>
   <Table selection={()=>selected.value?.key||''} table="stock" label="Inventory records" search={search} height={320} onSelect={event=>{selected.value=event.value;name.value=event.value.values.name;quantity.value=event.value.values.quantity;status.value='';}}/>
  </Column>
 </Column>;
}
mount(Inventory);
