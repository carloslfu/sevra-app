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
# LLGuidance preserves schema property order. Match the app's required-first
# ordering for nested JSON while leaving XML argument order unchanged.
def required_first(value):
    if isinstance(value, list): return [required_first(v) for v in value]
    if not isinstance(value, dict): return value
    result = {k: required_first(v) for k, v in sorted(value.items())}
    if 'properties' in result:
        props = result['properties']
        names = [k for k in result.get('required', []) if k in props]
        names += [k for k in ['componentID', 'definitionBinding'] if k in props and k not in names]
        names += sorted(k for k in props if k not in names)
        result['properties'] = {k: props[k] for k in names}
    return result
for tool in tools:
    props = tool['function']['parameters']['properties']
    for key in props: props[key] = required_first(props[key])
functions = {tool['function']['name']: tool['function']['parameters'] for tool in tools}
def ordered_value(value, schema):
    if isinstance(value, list): return [ordered_value(v, schema.get('items', {})) for v in value]
    if not isinstance(value, dict): return value
    props = schema.get('properties', {})
    names = [k for k in props if k in value] + sorted(k for k in value if k not in props)
    return {k: ordered_value(value[k], props.get(k, {})) for k in names}
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
        text = value if isinstance(value, str) else json.dumps(ordered_value(value, functions[name]['properties'][key]), ensure_ascii=False, separators=(',', ':'))
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
    elif name == 'draft': values.update(text='A new prose summary.')
    elif name == 'save_space':
        values.update(title='Overview', definition={'version':1,'components':[{'id':'table','type':'table','title':'Suppliers','datasetID':'table-1'}]})
    elif name == 'edit_space':
        values.update(id='home', expectedVersion=1, edits=[{'operation':'move','componentID':'tables','at':'first'}, {'operation':'remove','componentID':'recent'}])
    outputs.append((name, xml(name, values), values))
    if name == 'find_definitions':
        interpretations = {'query': '', 'kind': 'interpretation'}
        outputs.append(('find_definitions_interpretation', xml(name, interpretations), interpretations))
        extractions = {'query': '', 'kind': 'extraction'}
        outputs.append(('find_definitions_extraction', xml(name, extractions), extractions))
        intakes = {'query': '', 'kind': 'intake'}
        outputs.append(('find_definitions_intake', xml(name, intakes), intakes))
    if name in ('save_space', 'edit_space'):
        for kind in ('calculation', 'query'):
            component = {'id': 'result', 'type': kind, 'title': 'Reusable result',
                         'definitionBinding': {'mode': 'live', 'logicalID': 'definition-1'},
                         'arguments': {'amount': '3'}}
            composed = ({'title': 'Results', 'definition': {'version': 1, 'components': [component]}}
                        if name == 'save_space' else
                        {'id': 'home', 'expectedVersion': 1,
                         'edits': [{'operation': 'insert', 'at': 'first', 'component': component}]})
            outputs.append((name + '_' + kind, xml(name, composed), composed))
    if name == 'draft':
        composed = dict(values)
        composed.pop('text')
        composed['parts'] = [{'text':'Review\n'}, {'copy':'copy:123e4567-e89b-12d3-a456-426614174000:0:0:12'}]
        outputs.append(('draft_parts', xml(name, composed), composed))
    if name == 'propose_table':
        formulas = dict(values, columns=[{'id':'quantity','title':'Quantity','type':'decimal'},
                         {'id':'unit_cost','title':'Unit cost','type':'decimal'},
                         {'id':'total','title':'Total','type':'decimal','formula':'quantity*unit_cost'}],
                        rows=[{'quantity':'3','unit_cost':'2.50'}])
        outputs.append(('propose_table_formula', xml(name, formulas), formulas))

cases = []
choices = [('required', 'required', False, outputs),
           ('auto', 'auto', False, [('plain', 'The workbook is ready.', None), ('tool', 'Looking.\n' + outputs[0][1], outputs[0][2])]),
           ('named_finish', {'type':'function','function':{'name':'finish'}}, False, [next(v for v in outputs if v[0]=='finish')]),
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
result = dict(schemaVersion=1, nestedPropertyOrder='required-then-component-and-definition-selectors', splashCommit='1744cfafee415fb463b289449cec59a864e768e9',
              toolsSHA256=hashlib.sha256((ROOT/'IntegrationTests/Agent/workbook-tools.json').read_bytes()).hexdigest(),
              cases=cases)
path = ROOT/'IntegrationTests/Agent/tool-grammar-fixtures.json'
text = json.dumps(result, ensure_ascii=False, indent=2)+'\n'
if args.write: path.write_text(text)
elif path.read_text()!=text: raise RuntimeError('Workbook tool reference fixtures changed')
print(json.dumps({'tools':len(tools),'cases':len(cases),'masks':sum(len(c['steps']) for c in cases)}))
