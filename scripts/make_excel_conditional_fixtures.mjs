// Author synthetic conditional-sum cases; LibreOffice supplies independent cached results.
import fs from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
const require = createRequire(path.join(process.env.CODEX_NODE_MODULES, '../package.json'));
const {Workbook, SpreadsheetFile} = await import(require.resolve('@oai/artifact-tool'));
const root = 'integration/fixtures/excel-conditional';
const raw = '.build/excel-business/conditional-originals';
await fs.mkdir(root,{recursive:true});await fs.mkdir(raw,{recursive:true});
const rows = [
  ['Alpha',10,'Open'], ['ALPHA',20,'Closed'], ['Beta',30,'Open'],
  [2,40,'Open'], ['2',50,'Closed'], [0,60,'Open'], [null,70,'Open'],
  ['A*',80,'Open'], ['A?',90,'Closed'], ['A~',100,'Open'],
  ['abc',110,'Open'], ['=1/0',120,'Open'], ['Bad','=1/0','Closed']
];
const formulas = [
  'SUMIF(A1:A13,"Alpha",B1:B13)', 'SUMIF(A1:A13,A1,B1:B13)',
  'SUMIF(A1:A13,"<>Alpha",B1:B12)', 'SUMIF(A1:A12,"<>Alpha",B1:B12)',
  'SUMIF(A1:A12,2,B1:B12)', 'SUMIF(A1:A12,"2",B1:B12)',
  'SUMIF(A1:A12,">=2",B1:B12)', 'SUMIF(A1:A12,"<>2",B1:B12)',
  'SUMIF(A1:A12,0,B1:B12)', 'SUMIF(A1:A12,"",B1:B12)',
  'SUMIF(A1:A12,A7,B1:B12)', 'SUMIF(A1:A12,"<>",B1:B12)',
  'SUMIF(A1:A12,"A*",B1:B12)', 'SUMIF(A1:A12,"A?",B1:B12)',
  'SUMIF(A1:A12,"A~*",B1:B12)', 'SUMIF(A1:A12,"A~?",B1:B12)',
  'SUMIF(A1:A12,"A~~",B1:B12)', 'SUMIF(A1:A12,"<>A*",B1:B12)',
  'SUMIF(A1:A12,">Alpha",B1:B12)', 'SUMIF(A1:A12,"<Alpha",B1:B12)',
  'SUMIF(A1:A12,"#DIV/0!",B1:B12)', 'SUMIF(A1:A12,A12,B1:B12)',
  'SUMIF(A1:A12,"*",B1:B12)', 'SUMIF(A1:A12,"=",B1:B12)',
  'SUMIF(B1:B12,">50")', 'SUMIF(A1:A3,"Alpha",B1)',
  'SUMIFS(B1:B12,A1:A12,"A*",C1:C12,"Open")',
  'SUMIFS(B1:B12,A1:A12,">=2",C1:C12,"Closed")',
  'SUMIFS(B1:B12,A1:A11,"Alpha")', 'SUMIF(A1,"Alpha",B1)',
  'SUMIF(A1:A12,"*?*?*",B1:B12)', 'SUMIFS(B1:B13,C1:C13,"Closed")'
];
const wb=Workbook.create();const sheet=wb.worksheets.add('Criteria');
for(let r=0;r<rows.length;r++)for(let c=0;c<3;c++){
  const value=rows[r][c]; const range=sheet.getRangeByIndexes(r,c,1,1);
  if(typeof value==='string'&&value.startsWith('='))range.formulas=[[value]];
  else if(value!==null)range.values=[[value]];
}
formulas.forEach((formula,index)=>{sheet.getRange(`E${index+1}`).formulas=[['='+formula]];});
await (await SpreadsheetFile.exportXlsx(wb)).save(path.join(raw,'criteria.xlsx'));
await fs.writeFile(path.join(root,'cases.json'),JSON.stringify({rows,formulas},null,2)+'\n');
console.log(`Authored ${formulas.length} conditional-sum checks.`);
