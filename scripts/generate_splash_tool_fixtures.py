#!/usr/bin/env python3
"""Reference masks for the actual workbook tools, using pinned Splash Python only."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import sys
from splash_reference_identity import verify

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('model', type=Path)
parser.add_argument('--write', action='store_true')
args = parser.parse_args()
sys.path.insert(0, str(verify(ROOT, args.model)))
assert importlib.metadata.version('llguidance') == '1.8.0'
from transformers import AutoTokenizer
from server.chat_format import QWEN
from server.constraints import ConstraintFactory
from server.tool_schema import normalize_tools, tool_grammar

tokenizer = AutoTokenizer.from_pretrained(str(args.model.resolve()), local_files_only=True)
factory = ConstraintFactory(tokenizer, QWEN)
tools = json.loads((ROOT/'IntegrationTests/Agent/workbook-tools.json').read_text())
def example(schema):
    if 'const' in schema: return schema['const']
    if 'enum' in schema: return schema['enum'][0]
    kind = schema.get('type')
    if kind == 'object': return {key: example(schema['properties'][key]) for key in schema.get('required', [])}
    if kind == 'array': return [example(schema['items']) for _ in range(max(1, schema.get('minItems', 0)))]
    if kind == 'string': return 'example'
    if kind == 'integer': return 1
    if kind == 'number': return 1.25
    if kind == 'boolean': return True
    if kind == 'null': return None
    raise ValueError('Unsupported example schema')
def xml(name, arguments):
    fields = ''
    for key, value in sorted(arguments.items()):
        text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, separators=(',', ':'), sort_keys=True)
        fields += f'<parameter={key}>\n{text}\n</parameter>\n'
    return f'<tool_call>\n<function={name}>\n{fields}</function>\n</tool_call>'

outputs = []
for tool in tools:
    function = tool['function']
    name = function['name']
    values = example(function['parameters'])
    if name == 'propose_table':
        values.update(title='Suppliers', meaning='plan', inputs=['source-1'], columns=[{'id':'price','title':'Price','type':'decimal'}], rows=[{'price':'12.40','note':None}])
    elif name == 'propose_table_edit':
        values.update(datasetID='table-1', edits=[{'id':'row-1','values':{'price':'12.50','note':None}}])
    elif name == 'calculate': values.update(expression='cost * 2', values={'cost':'12.40'})
    elif name == 'propose_record': values.update(data={'units':12,'note':None}, meaning='estimate')
    elif name == 'save_space':
        values.update(title='Overview', definition={'version':1,'components':[{'id':'table','type':'table','title':'Suppliers','datasetID':'table-1'}]})
    outputs.append((name, xml(name, values), values))

cases = []
choices = [('required', 'required', False, outputs),
           ('auto', 'auto', False, [('plain', 'The workbook is ready.', None), ('tool', 'Looking.\n' + outputs[0][1], outputs[0][2])]),
           ('named_finish', {'type':'function','function':{'name':'finish'}}, False, [outputs[-1]]),
           ('thinking', 'required', True, [('reasoned', 'Read the evidence.</think>\n' + outputs[0][1], outputs[0][2])])]
for choice_name, choice, thinking, examples in choices:
    _, policy = normalize_tools(tools, choice, False)
    grammar = tool_grammar(policy, thinking, chat_format=QWEN)
    for name, output, arguments in examples:
        tokens = tokenizer.encode(output, add_special_tokens=False)
        constraint = factory.create(grammar)
        steps = []
        offsets = sorted(set([0, 1, 2, len(tokens)] + list(range(8, len(tokens), 8))))
        consumed = 0
        for offset in offsets:
            constraint.commit(tokens[consumed:offset])
            consumed = offset
            simulation = tokens[offset:offset+8]
            masks = constraint.masks(simulation)
            steps.append(dict(committed=tokens[:offset], simulation=simulation, maskSHA256=hashlib.sha256(masks).hexdigest()))
        constraint.finish()
        assert constraint.matcher.is_accepting()
        cases.append(dict(name=choice_name+'_'+name, choice=choice_name, thinking=thinking,
                          output=output, arguments=arguments, tokens=tokens, steps=steps))
result = dict(schemaVersion=1, splashCommit='1744cfafee415fb463b289449cec59a864e768e9',
              toolsSHA256=hashlib.sha256((ROOT/'IntegrationTests/Agent/workbook-tools.json').read_bytes()).hexdigest(),
              cases=cases)
path = ROOT/'IntegrationTests/Agent/tool-grammar-fixtures.json'
text = json.dumps(result, ensure_ascii=False, indent=2)+'\n'
if args.write: path.write_text(text)
elif path.read_text()!=text: raise RuntimeError('Workbook tool reference fixtures changed')
print(json.dumps({'tools':len(tools),'cases':len(cases),'masks':sum(len(c['steps']) for c in cases)}))
