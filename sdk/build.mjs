import {build} from 'esbuild';
import {readFile,writeFile,mkdir,copyFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=path.dirname(fileURLToPath(import.meta.url));
const resource=path.resolve(root,'../Sources/SevraAppRuntime/Resources');
await mkdir(resource,{recursive:true});
await build({entryPoints:[root+'/src/runtime.ts'],bundle:true,format:'iife',globalName:'Sevra',platform:'neutral',target:'es2020',outfile:resource+'/sdk.js',legalComments:'inline'});
await copyFile(root+'/node_modules/@preact/signals-core/LICENSE',resource+'/Signals-LICENSE.txt');
if (process.argv[2]) {
 const dir=path.resolve(process.argv[2]); const manifest=JSON.parse(await readFile(dir+'/app.json','utf8'));
 const result=await build({entryPoints:[dir+'/main.tsx'],bundle:true,format:'iife',platform:'neutral',target:'es2020',write:false,jsxFactory:'Sevra.h',jsxFragment:'Sevra.Fragment',plugins:[{name:'sevra',setup(b){b.onResolve({filter:/^@sevra\/sdk$/},()=>({path:'sevra',namespace:'sdk'}));b.onLoad({filter:/.*/,namespace:'sdk'},()=>({contents:'module.exports = Sevra;',loader:'js'}));}}]});
 const output=process.argv[3]||dir+'/app.sevraapp';
 await writeFile(output,JSON.stringify({...manifest,sdkVersion:1,source:result.outputFiles[0].text},null,2)+'\n');
 console.log(output);
}
