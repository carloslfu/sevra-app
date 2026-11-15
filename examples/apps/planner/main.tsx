import {Column,Row,Text,TextField,Button,Canvas,signal,draftSignal,liveQuery,data,mount,action} from '@sevra/sdk';
function Planner() {
 const title=draftSignal('title',''), status=signal(''), cards=liveQuery({table:'cards',limit:100});
 const addCard=action('addCard',{title:'Add a card',inputs:{title:{type:'text',title:'Card title'}}},async({title})=>{
  if(!title.trim())throw Error('Enter a card title.');
  const receipt=await data.transaction([{op:'insert',table:'cards',values:{title,x:String(20+(cards.value.rows.length%2)*170),y:String(25+Math.floor(cards.value.rows.length/2)*90)}}]);status.value='Card saved.';return receipt;
 });
 const moveCard=action('moveCard',{title:'Position a card',inputs:{rowID:{type:'record',title:'Card'},x:{type:'number',title:'Horizontal position'},y:{type:'number',title:'Vertical position'}}},async({rowID,x,y})=>{
  const receipt=await data.transaction([{op:'update',table:'cards',id:rowID,values:{x:String(Math.max(0,Math.min(300,x))),y:String(Math.max(0,y))}}]);status.value='Position saved.';return receipt;
 });
 async function add() {
  if(!title.value.trim()){status.value='Enter a card title.';return;}
  try {await addCard({title:title.value});title.value='';status.value='Card saved.';}catch(error){status.value=error.message;}
 }
 async function move(event) {
  const row=cards.value.rows.find(row=>row.key===event.value);if(!row)return;
  try {await moveCard({rowID:row.id,x:Number(row.values.x)+event.x,y:Number(row.values.y)+event.y});status.value='Position saved.';}catch(error){status.value=error.message;}
 }
 return <Column gap={12}>
  <Text text="Plan your work" size={26} weight="bold"/>
  <Text text="Drag a card to move it. Arrow keys move the selected card."/>
  <Text text={()=>`Showing ${cards.value.rows.length} of ${cards.value.total||0} cards.`}/>
  <Row><TextField label="Card title" placeholder="Card title" value={title} width={260}/><Button title="Add card" onClick={add}/></Row>
  <Text text={status} hidden={()=>!status.value}/>
  <Canvas label="Planning board" width={450} height={()=>Math.max(420,...cards.value.rows.map(row=>Number(row.values.y)+100))}
   shapes={()=>cards.value.rows.flatMap(row=>[{id:row.key,type:'rect',x:Number(row.values.x),y:Number(row.values.y),width:150,height:66,color:'accent'},{id:row.key,type:'text',x:Number(row.values.x)+12,y:Number(row.values.y)+20,text:row.values.title,color:'background'}])}
   regions={()=>cards.value.rows.map(row=>({id:row.key,label:row.values.title,x:Number(row.values.x),y:Number(row.values.y),width:150,height:66}))}
   onClick={event=>{status.value='Selected card.';}} onDrop={move}/>
 </Column>;
}
mount(Planner);
