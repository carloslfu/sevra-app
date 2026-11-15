// Synthetic business sources. Expected results come from spreadsheet formulas,
// independently recalculated by LibreOffice, never from a reference mini app.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
const require = createRequire(path.join(process.env.CODEX_NODE_MODULES, '../package.json'));
const {Workbook, SpreadsheetFile} = await import(require.resolve('@oai/artifact-tool'));
const root = 'integration/fixtures/excel-business';
const raw = '.build/excel-business/originals';
await fs.mkdir(raw, {recursive:true});
await fs.mkdir(root, {recursive:true});
const SUM = (sheet,col,keycol,key) => `SUMIF('${sheet}'!$${keycol}$2:$${keycol}$1000,${key},'${sheet}'!$${col}$2:$${col}$1000)`;
const records = (prefix,n,make) => Array.from({length:n},(_,i)=>make(i,`${prefix}${i+1}`));
const cases = [
  {
    name:'Stock and purchasing',slug:'stock',
    sheets:[
      ['Products',[['SKU','Product','Opening','Unit cost','Reorder'],['P1','Copper fitting',40,2.5,20],['P2','Seal kit',25,6,10],['P3','Valve',18,12,8]]],
      ['Movements',[['Reference','SKU','Quantity','Kind'],...records('M',12,(i,id)=>[id,`P${i%3+1}`,i%2===0?5:-2,i%2===0?'Receipt':'Shipment'])]],
      ['Stock',[['SKU','Available','Value','Reorder quantity'],...[2,3,4].map(r=>[`=Products!A${r}`,`=Products!C${r}+${SUM('Movements','C','B',`A${r}`)}`,`=B${r}*Products!D${r}`,`=MAX(0,Products!E${r}-B${r})`])]]
    ],
    purpose:'Manage a synthetic plumbing supplier. Expose Receive stock and Ship stock actions taking Reference, SKU and Quantity; reference must be unique, SKU must exist, quantity positive, and shipping must not overdraw stock. Append signed movements, never change opening stock. Expose Update unit cost for a known SKU, using explicit supplied prices. Show all three sheets with clear names and current available/value/reorder values. Native controls and named conversation actions must share rules. Include Undo.',
    edits:[['Products','D2',3.75],['Movements','C3',-8]],
    journeys:[
      {request:'Receive 7 units of P1 under reference TEST-R1.',argumentValues:['7'],sheet:'Movements',match:{A:'TEST-R1'},values:{B:'P1',C:'7'}},
      {request:'Ship 3 units of P1 under reference TEST-S1.',argumentValues:['3'],sheet:'Movements',match:{A:'TEST-S1'},values:{B:'P1',C:'-3'}},
      {request:'Ship 9999 units of P1 under reference TEST-INVALID.',unchanged:true},
      {request:'Receive 7 units of P1 under reference TEST-R1 again.',unchanged:true},
      {request:'Set the unit cost of P1 to 3.75.',sheet:'Products',match:{A:'P1'},values:{D:'3.75'}},
      {request:'Update unit costs for the products listed in the supplied price file.',inputFile:'stock-prices.csv',sheet:'Products',match:{A:'P2'},values:{D:'7.25'}}
    ]
  },
  {
    name:'Invoicing and payments',slug:'invoices',
    sheets:[
      ['Customers',[['Customer','Name','Credit limit'],['C1','Juniper Studio',5000],['C2','Maple Workshop',3000],['C3','Cedar Services',2000]]],
      ['Ledger',[['Reference','Customer','Kind','Amount'],...records('I',12,(i,id)=>[id,`C${i%3+1}`,i%4===3?'Payment':'Invoice',i%4===3?-50:100+i*10])]],
      ['Receivables',[['Customer','Balance','Available credit'],...[2,3,4].map(r=>[`=Customers!A${r}`,`=${SUM('Ledger','D','B',`A${r}`)}`,`=Customers!C${r}-B${r}`])]]
    ],
    purpose:'Manage synthetic service invoices and payments. Create invoice and Record payment take Reference, Customer and Amount. Reject duplicate references and unknown customers; require positive amounts. Store invoices positive and payments negative in Ledger, including partial payments. Issue credit uses a positive entered amount stored negative with Kind Credit. Preserve balances and available credit. Show each sheet. Expose each operation as a named conversation action and a native form using the same function; include Undo.',
    edits:[['Ledger','D2',240],['Ledger','D5',-120]],
    journeys:[
      {request:'Create invoice TEST-I1 for customer C1 for 240.',argumentValues:['240'],sheet:'Ledger',match:{A:'TEST-I1'},values:{B:'C1',C:'Invoice',D:'240'}},
      {request:'Record payment TEST-P1 from customer C1 for 80.',argumentValues:['80'],sheet:'Ledger',match:{A:'TEST-P1'},values:{B:'C1',C:'Payment',D:'-80'}},
      {request:'Issue credit TEST-C1 to customer C1 for 20.',argumentValues:['20'],sheet:'Ledger',match:{A:'TEST-C1'},values:{B:'C1',C:'Credit',D:'-20'}},
      {request:'Create invoice TEST-I1 for C1 for 240 again.',unchanged:true},
      {request:'Create invoice TEST-INVALID for customer UNKNOWN for 100.',unchanged:true}
    ]
  },
  {
    name:'Job costing',slug:'jobs',
    sheets:[
      ['Staff',[['Employee','Name','Hourly cost'],['E1','Avery',24],['E2','Jordan',30],['E3','Morgan',36]]],
      ['Time',[['Reference','Job','Employee','Hours'],...records('T',12,(i,id)=>[id,`J${i%3+1}`,`E${i%3+1}`,i%4+1])]],
      ['Jobs',[['Job','Budget revenue','Hours','Labor cost','Margin'],...[2,3,4].map((r,i)=>[`J${i+1}`,1000+i*500,`=${SUM('Time','D','B',`A${r}`)}`,`=SUMPRODUCT(('Time'!$B$2:$B$1000=A${r})*('Time'!$C$2:$C$1000=Staff!A2)*'Time'!$D$2:$D$1000)*Staff!C2+SUMPRODUCT(('Time'!$B$2:$B$1000=A${r})*('Time'!$C$2:$C$1000=Staff!A3)*'Time'!$D$2:$D$1000)*Staff!C3+SUMPRODUCT(('Time'!$B$2:$B$1000=A${r})*('Time'!$C$2:$C$1000=Staff!A4)*'Time'!$D$2:$D$1000)*Staff!C4`,`=B${r}-D${r}`])]]
    ],
    purpose:'Manage synthetic job time and profitability. Log time takes Reference, Job, Employee and Hours; require a unique reference, existing job and employee, and positive hours at most 24. Append the Time ledger. Update hourly cost takes Employee and Hourly cost; nonnegative rates apply to all recorded time, as in the source. Costs join by employee key and job key, never row position. Show every sheet. Expose named conversation actions and native controls calling the same functions; include Undo.',
    edits:[['Time','D2',6],['Staff','C3',35]],
    journeys:[
      {request:'Log time TEST-T1 for employee E2 on job J1: 3.5 hours.',sheet:'Time',match:{A:'TEST-T1'},values:{B:'J1',C:'E2',D:'3.5'}},
      {request:'Set hourly cost for employee E2 to 35.',sheet:'Staff',match:{A:'E2'},values:{C:'35'}},
      {request:'Log time TEST-INVALID for employee UNKNOWN on job J1: 2 hours.',unchanged:true},
      {request:'Log time TEST-INVALID for employee E1 on job J1: 25 hours.',unchanged:true},
      {request:'Log time TEST-T2 for employee E1 on job J2: 4 hours.',sheet:'Time',match:{A:'TEST-T2'},values:{B:'J2',C:'E1',D:'4'}}
    ]
  },
  {
    name:'Production planning',slug:'production',
    sheets:[
      ['Materials',[['Material','Opening','Units per batch'],['Steel',200,4],['Resin',120,3],['Packaging',100,1]]],
      ['Runs',[['Reference','Batches','Status'],...records('R',8,(i,id)=>[id,i%2+1,i%3===0?'Planned':'Completed'])]],
      ['Capacity',[['Material','Used','Available','Planned demand','Shortage'],...[2,3,4].map(r=>[`=Materials!A${r}`,`=${SUM('Runs','B','C','"Completed"')}*Materials!C${r}`,`=Materials!B${r}-B${r}`,`=${SUM('Runs','B','C','"Planned"')}*Materials!C${r}`,`=MAX(0,D${r}-C${r})`])]]
    ],
    purpose:'Manage synthetic single-product production with three materials in Materials. Plan run takes unique Reference and positive integer Batches, appending a Planned row. Complete run takes Reference, validates it exists and is Planned, checks every material has enough available stock, then changes its status to Completed atomically. Cancel run only cancels a Planned run by setting Cancelled. Never partially consume stock or complete twice. Capacity formulas determine consumption and shortages. Show all sheets; shared named conversation and native actions; include Undo.',
    edits:[['Runs','B2',8],['Materials','B3',20]],
    journeys:[
      {request:'Plan production run TEST-R1 for 3 batches.',sheet:'Runs',match:{A:'TEST-R1'},values:{B:'3',C:'Planned'}},
      {request:'Complete production run TEST-R1.',sheet:'Runs',match:{A:'TEST-R1'},values:{C:'Completed'}},
      {request:'Complete production run TEST-R1 again.',unchanged:true},
      {request:'Plan production run TEST-R2 for 999 batches.',sheet:'Runs',match:{A:'TEST-R2'},values:{B:'999',C:'Planned'}},
      {request:'Complete production run TEST-R2.',unchanged:true},
      {request:'Cancel production run TEST-R2.',sheet:'Runs',match:{A:'TEST-R2'},values:{C:'Cancelled'}}
    ]
  },
  {
    name:'Cash and loans',slug:'cash',
    sheets:[
      ['Assumptions',[['Opening cash','Principal','Annual rate','Months'],[15000,12000,0.06,12]]],
      ['Cashbook',[['Reference','Month','Amount','Description'],...records('C',12,(i,id)=>[id,i%3+1,i%2===0?1200:-450,i%2===0?'Customer receipt':'Supplier payment'])]],
      ['Forecast',[['Month','Opening cash','Net receipts','Loan payment','Closing cash'],...[2,3,4].map((r,i)=>[i+1,r===2?'=Assumptions!A2':`=E${r-1}`,`=${SUM('Cashbook','C','B',`A${r}`)}`,'=ROUND(-PMT(Assumptions!C2/12,Assumptions!D2,Assumptions!B2),2)',`=B${r}+C${r}-D${r}`])]]
    ],
    purpose:'Manage a synthetic three-month cash forecast with a fixed-payment loan. Add cash entry takes Reference, Month (integer 1 through 3), Amount (signed, nonzero), and Description; reject duplicate references. Update loan takes Principal (nonnegative), Annual rate (decimal fraction, nonnegative) and Months (positive integer). Preserve PMT zero-interest behavior and two-decimal payment rounding, month boundaries and rolling cash. Show all sheets; named conversation actions and native controls share implementation; include Undo.',
    edits:[['Assumptions','C2',0],['Cashbook','C2',-800]],
    journeys:[
      {request:'Add cash entry TEST-C1 in month 2 for -125.50, description Machine maintenance.',sheet:'Cashbook',match:{A:'TEST-C1'},values:{B:'2',C:'-125.50',D:'Machine maintenance'}},
      {request:'Update loan to principal 12000, annual rate 0, and 12 months.',sheet:'Assumptions',match:{A:'15000'},values:{B:'12000',C:'0',D:'12'}},
      {request:'Add cash entry TEST-INVALID in month 4 for 100, description Invalid period.',unchanged:true},
      {request:'Update loan to principal 12000, annual rate 0.06, and 0 months.',unchanged:true},
      {request:'Add cash entry TEST-C2 in month 1 for 250, description Deposit.',sheet:'Cashbook',match:{A:'TEST-C2'},values:{B:'1',C:'250',D:'Deposit'}}
    ]
  },
  {
    name:'Service bookings',slug:'bookings',
    sheets:[
      ['Resources',[['Resource','Name','Hourly price','Weekly hours'],['B1','Studio North',45,40],['B2','Studio South',60,40],['B3','Meeting room',25,30]]],
      ['Bookings',[['Reference','Resource','Day','Start hour','Hours','Customer','Status'],...records('B',9,(i,id)=>[id,`B${i%3+1}`,i<3?'Monday':i<6?'Tuesday':'Wednesday',9,2,`Client ${i+1}`,'Booked'])]],
      ['Utilization',[['Resource','Booked hours','Revenue','Free hours'],...[2,3,4].map(r=>[`=Resources!A${r}`,`=SUMIFS(Bookings!$E$2:$E$1000,Bookings!$B$2:$B$1000,A${r},Bookings!$G$2:$G$1000,"Booked")`,`=B${r}*Resources!C${r}`,`=Resources!D${r}-B${r}`])]]
    ],
    purpose:'Manage synthetic weekday room bookings. Add booking takes Reference, Resource, Day (Monday through Friday), Start hour, Hours and Customer. Require unique reference, known resource, nonblank customer, positive hours, integer start hour from 8 through 17 and end no later than 18. Reject overlapping Booked intervals for the same resource/day. Reschedule booking takes Reference, Day and Start hour, preserves duration/customer and applies the same overlap rules excluding itself. Cancel booking sets Cancelled; cancelled bookings do not consume capacity/revenue. Show all sheets. Use shared named conversation/native actions and include Undo. Ask for missing required inputs rather than guessing.',
    edits:[['Bookings','E2',3],['Resources','C3',75]],
    journeys:[
      {request:'Add booking TEST-B1 for resource B1 on Thursday starting at 10 for 2 hours, customer Willow Studio.',sheet:'Bookings',match:{A:'TEST-B1'},values:{B:'B1',C:'Thursday',D:'10',E:'2',F:'Willow Studio',G:'Booked'}},
      {request:'Add booking TEST-CONFLICT for resource B1 on Thursday starting at 11 for 2 hours, customer Oak Studio.',unchanged:true},
      {request:'Reschedule booking TEST-B1 to Friday at 14.',sheet:'Bookings',match:{A:'TEST-B1'},values:{C:'Friday',D:'14'}},
      {request:'Cancel booking TEST-B1.',sheet:'Bookings',match:{A:'TEST-B1'},values:{G:'Cancelled'}},
      {request:'Add a booking for resource B2 on Friday.',unchanged:true,clarification:true}
    ]
  }
];
const manifest=[];
for(const example of cases){
  const files=[];
  for(let variant=0;variant<3;variant++){
    const wb=Workbook.create();
    for(const [name] of example.sheets)wb.worksheets.add(name);
    for(const [name,rows] of example.sheets){
      const sheet=wb.worksheets.getItem(name);
      const values=rows.map(row=>row.map(x=>typeof x==='string'&&x.startsWith('=')?null:x));
      sheet.getRangeByIndexes(0,0,rows.length,rows[0].length).values=values;
      rows.forEach((row,r)=>row.forEach((x,c)=>{if(typeof x==='string'&&x.startsWith('='))sheet.getCell(r,c).formulas=[[x]];}));
      sheet.showGridLines=false;
      const range=sheet.getRangeByIndexes(0,0,rows.length,rows[0].length);
      range.format.font.name='Arial';range.format.font.size=10;
      range.format.verticalAlignment='center';range.format.rowHeight=24;range.format.columnWidth=20;
      const header=sheet.getRangeByIndexes(0,0,1,rows[0].length);
      header.format.fill='#293E52';header.format.font.color='#FFFFFF';header.format.font.bold=true;
      if(rows.length>8)sheet.freezePanes.freezeRows(1);
    }
    if(variant){const [sheet,cell,value]=example.edits[variant-1];wb.worksheets.getItem(sheet).getRange(cell).values=[[value]];}
    wb.recalculate();
    const file=`${example.slug}-${variant}.xlsx`;files.push(file);
    await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(raw,file));
    if(variant===0){
      for(const [name,rows] of example.sheets){
        const range=`A1:${String.fromCharCode(64+rows[0].length)}${rows.length}`;
        const preview=await wb.render({sheetName:name,range,scale:1.5});
        await fs.writeFile(path.join(raw,`${example.slug}-${name}.png`),new Uint8Array(await preview.arrayBuffer()));
      }
      const inspection=await wb.inspect({kind:'sheet,table',maxChars:12000,tableMaxRows:20,tableMaxCols:8});
      await fs.writeFile(path.join(raw,`${example.slug}-inspection.txt`),inspection.ndjson);
    }
  }
  manifest.push({...example,files,sheets:example.sheets.map(([name])=>name)});
}
await fs.writeFile(path.join(root,'cases.json'),JSON.stringify(manifest,null,2)+'\n');
await fs.writeFile(path.join(root,'stock-prices.csv'),'SKU,Unit cost\nP2,7.25\n');
console.log(`Created ${manifest.length} synthetic applications, 18 originals and 18 source-sheet previews in ${raw}. Recalculate independently before use.`);
