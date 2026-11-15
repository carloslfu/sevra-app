// Synthetic SUMPRODUCT cases. Independent LibreOffice recalculation supplies answers.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
const require=createRequire(path.join(process.env.CODEX_NODE_MODULES,'../package.json'));
const {Workbook,SpreadsheetFile}=await import(require.resolve('@oai/artifact-tool'));
const root='integration/fixtures/excel-product';
const raw='.build/excel-business/product-originals';
await fs.mkdir(root,{recursive:true});await fs.mkdir(raw,{recursive:true});
const rows=[['A',2,3],['B',4,5],['a',6,7],['B',null,9],['C','bad',11],['D','=1/0',13],['E','2',17]];
const formulas=[
  'SUMPRODUCT(B1:B3,C1:C3)', 'SUMPRODUCT(B1:B3*C1:C3)',
  'SUMPRODUCT((A1:A4="a")*B1:B4)', 'SUMPRODUCT((A1:A4<>"a")*C1:C4)',
  'SUMPRODUCT((A1:A4="a")*(C1:C4>4)*B1:B4)',
  'SUMPRODUCT(A1:A4="a")', 'SUMPRODUCT(--(A1:A4="a"))',
  'SUMPRODUCT((A1:A4="a"),B1:B4)', 'SUMPRODUCT(B1:B4*2)',
  'SUMPRODUCT(B1:B4,2)', 'SUMPRODUCT(B1:B3,C1:C4)',
  'SUMPRODUCT(B1:C2)', 'SUMPRODUCT(B1:C2,B2:C3)',
  'SUMPRODUCT(B1:C2,B1:B4)', 'SUMPRODUCT(B1:B4)',
  'SUMPRODUCT(B1:B5,C1:C5)', 'SUMPRODUCT(B1:B5*C1:C5)',
  'SUMPRODUCT(B1:B6,C1:C6)', 'SUMPRODUCT((A1:A6="a")*B1:B6)',
  'SUMPRODUCT(B7,C7)', 'SUMPRODUCT(B7*C7)',
  'SUMPRODUCT(B1:B4/C1:C4)', 'SUMPRODUCT(C1:C4/B1:B4)',
  'SUMPRODUCT(-B1:B3)', 'SUMPRODUCT(B1:B3%)',
  'SUMPRODUCT((B1:B3+C1:C3)*2)', 'SUMPRODUCT(B1:B3-SUM(C1:C3))',
  'SUMPRODUCT(B1:B3*"2")', 'SUMPRODUCT(B1:B3*"bad")',
  'SUMPRODUCT(2,3)', 'SUMPRODUCT(B1:B3/B1:B3)',
  'SUMPRODUCT((A1:A4="a")+(A1:A4="B"))',
  'SUMPRODUCT(B1:B3>=4)', 'SUMPRODUCT((B1:B3>=4)*1)',
  'SUMPRODUCT((A1:A4="A")*(C1:C4<=7),B1:B4)',
];
const wb=Workbook.create();const sheet=wb.worksheets.add('Products');
for(let r=0;r<rows.length;r++)for(let c=0;c<3;c++){
  const value=rows[r][c],cell=sheet.getCell(r,c);
  if(typeof value==='string'&&value.startsWith('='))cell.formulas=[[value]];
  else if(value!==null)cell.values=[[value]];
}
formulas.forEach((formula,index)=>sheet.getCell(index,4).formulas=[['='+formula]]);
await(await SpreadsheetFile.exportXlsx(wb)).save(path.join(raw,'products.xlsx'));
await fs.writeFile(path.join(root,'cases.json'),JSON.stringify({rows,formulas},null,2)+'\n');
console.log(`Authored ${formulas.length} array calculation cases.`);
