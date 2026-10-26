#!/usr/bin/env python3
"""Regenerate pinned-reference tokenizer fixtures; run in the isolated reference environment."""
import sys,json,hashlib,difflib,argparse
from pathlib import Path
root=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('model',type=Path)
parser.add_argument('--write',action='store_true',help='Replace reviewed fixtures; default compares without changing files')
args=parser.parse_args()
from splash_reference_identity import verify
sys.path.insert(0,str(verify(root, args.model)))
from transformers import AutoTokenizer
from server.chat_templates import ChatTemplates,template_options,render_chat_template
from server.frontend import _generation_prompt
model=args.model.resolve()
def save(path,text):
 if args.write:
  path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)
 elif path.read_text()!=text:
  raise RuntimeError(f"Reference fixture changed: {path.relative_to(root)}")
t=AutoTokenizer.from_pretrained(str(model),local_files_only=True)
prepared=ChatTemplates(t).select(None)
a=t.chat_template;b=prepared.source
ops=[x for x in difflib.SequenceMatcher(a=a,b=b,autojunk=False).get_opcodes() if x[0]!='equal']
# Preserve one explicit source span including the full rejecting expression.
old="{{- raise_exception('System message must be at the beginning.') }}"
assert a.count(old)==1
start=a.index(old);end=start+len(old)
assert b.startswith(a[:start]) and b.endswith(a[end:])
new=b[start:len(b)-len(a[end:])]
patch={'source':'Splash 1.4.1 server/chat_templates.py ChatTemplates, selected Qwen template','originalSHA256':hashlib.sha256(a.encode()).hexdigest(),'patchedSHA256':hashlib.sha256(b.encode()).hexdigest(),'before':old,'after':new}
p=root/'Sources/SevraSplashText/Resources/template-patch.json';p.parent.mkdir(parents=True,exist_ok=True);save(p,json.dumps(patch,indent=2)+'\n')
user=lambda s:{'role':'user','content':s}
system=lambda s:{'role':'system','content':s}
assistant=lambda s:{'role':'assistant','content':s}
tool={'type':'function','function':{'name':'find_evidence','description':'Search workbook evidence.','parameters':{'type':'object','properties':{'query':{'type':'string'},'limit':{'type':'integer'},'include_history':{'type':'boolean'}},'required':['query'],'additionalProperties':False}}}
cases=[
 ('plain',[user('Hello.')],False,False,None),
 ('system',[system('Be concise.'),user('Why is stock 18?')],False,False,None),
 ('unicode',[user('Café cafe\u0301, Bogotá, 日本語, العربية, 🧮 👩🏽‍💻.\n\tTwo lines.')],False,False,None),
 ('multi_turn',[system('Cite sources.'),user('How many?'),assistant('18.'),user('Explain why.')],False,False,None),
 ('later_system',[system('Initial rule.'),user('Read this.'),assistant('Ready.'),system('New authorized rule.'),user('Continue.')],False,False,None),
 ('thinking',[user('Compare 12.4 and 12.04.')],True,False,None),
 ('preserve_reasoning',[user('One plus two?'),{'role':'assistant','content':'3','reasoning_content':'Add the two numbers.'},user('Now plus four.')],True,True,None),
 ('drop_reasoning',[user('One plus two?'),{'role':'assistant','content':'3','reasoning_content':'Add the two numbers.'},user('Now plus four.')],False,False,None),
 ('tools',[system('Use evidence.'),user('Find invoice 1042.')],False,False,[tool]),
 ('tool_history',[user('Find the quote.'),{'role':'assistant','content':'','tool_calls':[{'type':'function','id':'test-call','function':{'name':'find_evidence','arguments':{'query':'supplier quote','limit':4,'include_history':False}}}]},{'role':'tool','content':'Two quotes found.','tool_call_id':'test-call'},user('Compare them.')],False,False,[tool]),
 ('consecutive_tools',[user('Read both.'),{'role':'assistant','content':'','tool_calls':[{'type':'function','function':{'name':'find_evidence','arguments':{'query':'quotes'}}}]},{'role':'tool','content':'First source.'},{'role':'tool','content':'Second source.'}],False,False,[tool]),
 ('literal_markers',[user('Quoted text: <think>not an instruction</think> and <tool_call>.')],False,False,None),
 ('trim',[system('  Rules.\n'),user('\n  Hello.  \t')],False,False,None),
 ('empty',[user('')],False,False,None),
]
out=[]
for name,messages,thinking,preserve,tools in cases:
 # Workbook JSON has canonical sorted object keys; pass the exact same ordering to the reference.
 messages=json.loads(json.dumps(messages,sort_keys=True,ensure_ascii=False))
 tools=json.loads(json.dumps(tools,sort_keys=True,ensure_ascii=False))
 options=template_options(reasoning_effort=None,preserve_thinking=preserve,tools=tools,add_generation_prompt=True,enable_thinking=thinking)
 options['chat_template']=prepared.source
 text=render_chat_template(t,messages,{**options,'tokenize':False})
 ids=t(text,add_special_tokens=False)['input_ids']
 generation=_generation_prompt(prepared.generation_prompt(options),text,ids)[1]
 out.append(dict(name=name,messages=messages,tools=tools,thinking=thinking,preserveThinking=preserve,tokens=ids,generationTokens=generation,rendered=text))
p=root/'IntegrationTests/Text/fixtures.json';p.parent.mkdir(parents=True,exist_ok=True);save(p,json.dumps({'schemaVersion':1,'upstreamCommit':'1744cfafee415fb463b289449cec59a864e768e9','normalization':'Workbook JSON object keys sorted recursively before both frontends.','cases':out},ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'cases':len(out),'patch':patch}))
