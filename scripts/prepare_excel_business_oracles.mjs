// Author independent spreadsheet scenarios from observed INPUTS only. Never copy
// generated formula outputs into the oracle or expose oracle files to the model.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(path.join(process.env.CODEX_NODE_MODULES,'../package.json'));
const {SpreadsheetFile,FileBlob}=await import(require.resolve('@oai/artifact-tool'));
const root=process.argv[2];
if(!root)throw Error('Supply the retained trial directory');
const fixtures='integration/fixtures/excel-business';
const cases=JSON.parse(await fs.readFile(path.join(fixtures,'cases.json'),'utf8'));
const output=path.join(root,'oracle-inputs');
await fs.mkdir(output,{recursive:true});
const manifest=[];
for(const example of cases){
  let journeys;
  try{journeys=JSON.parse(await fs.readFile(path.join(root,`${example.slug}-journeys.json`),'utf8'));}
  catch(error){if(error.code==='ENOENT')continue;throw error;}
  for(const [index,journey] of journeys.entries()){
    const wb=await SpreadsheetFile.importXlsx(await FileBlob.load(path.join(fixtures,example.files[0])));
    const outputs=[];
    for(const [s,rows] of journey.state.entries()){
      const sheet=wb.worksheets.getItem(example.sheets[s]);
      const formulas=sheet.getUsedRange().formulas;
      for(const [r,row] of rows.entries()){
        for(const [field,value] of Object.entries(row)){
          if(!/^c[1-9][0-9]*$/.test(field))throw Error('Unexpected column');
          const c=Number(field.slice(1))-1;
          if(formulas[r]?.[c]){outputs.push({sheet:s,row:r,column:c,actual:value});continue;}
          // Imported worksheet cells are text in Sevra. Restore ordinary numeric
          // inputs to spreadsheet numbers; preserve literal keys/whitespace/blanks.
          const text=String(value??'');
          const number=/^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$/.test(text)&&Number.isFinite(Number(text));
          sheet.getCell(r,c).values=[[text===''?null:number?Number(text):text]];
        }
      }
    }
    wb.recalculate();
    const filename=`${example.slug}-${index}.xlsx`;
    await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(output,filename));
    manifest.push({file:filename,slug:example.slug,step:journey.step,outputs});
  }
}
if(!manifest.length)throw Error('No completed journey snapshots');
await fs.writeFile(path.join(root,'oracle-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(`Prepared ${manifest.length} independent scenarios from inputs.`);
