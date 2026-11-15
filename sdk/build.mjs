import {build} from 'esbuild';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
const root=path.dirname(fileURLToPath(import.meta.url));
const resource=path.resolve(root,'../Sources/SevraAppRuntime/Resources');
async function writeChanged(file,contents) {
 const bytes=Buffer.from(contents);
 try { if ((await readFile(file)).equals(bytes)) return; }
 catch (error) { if (error.code!=='ENOENT') throw error; }
 await writeFile(file,bytes);
}
await mkdir(resource,{recursive:true});
const runtime=await build({absWorkingDir:path.resolve(root,'..'),entryPoints:[root+'/src/runtime.ts'],bundle:true,format:'iife',globalName:'Sevra',platform:'neutral',target:'es2020',write:false,legalComments:'inline'});
await writeChanged(resource+'/sdk.js',runtime.outputFiles[0].contents);
await writeChanged(resource+'/Signals-LICENSE.txt',await readFile(root+'/node_modules/@preact/signals-core/LICENSE'));
if (process.argv[2]) {
 const dir=path.resolve(process.argv[2]); const manifest=JSON.parse(await readFile(dir+'/app.json','utf8'));
 const result=await build({absWorkingDir:path.resolve(root,'..'),entryPoints:[dir+'/main.tsx'],bundle:true,format:'iife',platform:'neutral',target:'es2020',write:false,jsxFactory:'Sevra.h',jsxFragment:'Sevra.Fragment',plugins:[{name:'sevra',setup(b){b.onResolve({filter:/^@sevra\/sdk$/},()=>({path:'sevra',namespace:'sdk'}));b.onLoad({filter:/.*/,namespace:'sdk'},()=>({contents:'module.exports = Sevra;',loader:'js'}));}}]});
 const output=process.argv[3]||dir+'/app.sevraapp';
 await writeChanged(output,JSON.stringify({...manifest,sdkVersion:1,source:result.outputFiles[0].text},null,2)+'\n');
 console.log(output);
}
