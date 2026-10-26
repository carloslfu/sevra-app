#!/usr/bin/env python3
"""Generate exact native-mask goldens with pinned Splash reference Python only."""
import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import subprocess
import sys
from splash_reference_identity import verify

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", type=Path)
parser.add_argument("--write", action="store_true")
args = parser.parse_args()
pin = json.loads((ROOT / "integration/splash.json").read_text())
upstream = verify(ROOT, args.model)
assert importlib.metadata.version("llguidance") == "1.8.0"
sys.path.insert(0, str(upstream))
from transformers import AutoTokenizer
from server.chat_format import QWEN
from server.constraints import ConstraintFactory
from server.tool_schema import json_grammar, tool_grammar, normalize_tools

tokenizer = AutoTokenizer.from_pretrained(str(args.model.resolve()), local_files_only=True)
factory = ConstraintFactory(tokenizer, QWEN)
simple = {"type": "object", "properties": {"answer": {"const": "ready"}},
          "required": ["answer"], "additionalProperties": False}
rich = {"type": "object", "properties": {"label": {"type": "string"}, "values": {
    "type": "array", "items": {"type": ["number", "boolean", "null"]}}},
    "required": ["label", "values"], "additionalProperties": False}
tools = [{"type": "function", "function": {"name": "find_evidence", "strict": True,
    "parameters": {"type": "object", "properties": {"query": {"type": "string"},
    "limit": {"type": "integer"}}, "required": ["query", "limit"], "additionalProperties": False}}}]
_, policy = normalize_tools(tools, "required", False)
cases = [
    ("json", json_grammar(simple, False, chat_format=QWEN), '{"answer":"ready"}'),
    ("unicode", json_grammar(rich, False, chat_format=QWEN),
     '{"label":"Bogotá, 日本語, 🧮 and \\"quote\\"","values":[1.25,-2,true,null]}'),
    ("reasoning_json", json_grammar(simple, True, chat_format=QWEN),
     'The requested value is ready.</think>\n\n{"answer":"ready"}'),
    ("strict_tool", tool_grammar(policy, False, chat_format=QWEN),
     '<tool_call>\n<function=find_evidence>\n<parameter=query>\ninvoice 1042\n</parameter>\n'
     '<parameter=limit>\n4\n</parameter>\n</function>\n</tool_call>'),
]
result = []
for name, grammar, output in cases:
    tokens = tokenizer.encode(output, add_special_tokens=False)
    constraint = factory.create(grammar)
    steps = []
    for index in range(len(tokens) + 1):
        if index:
            constraint.commit(tokens[index-1:index])
        simulation = tokens[index:index+8]
        masks = constraint.masks(simulation)
        steps.append({"committed": tokens[:index], "simulation": simulation,
                      "maskSHA256": hashlib.sha256(masks).hexdigest()})
    constraint.finish()
    assert constraint.matcher.is_accepting()
    for eos in QWEN.stop_ids:
        terminated = factory.create(grammar)
        terminated.commit(tokens)
        terminated.finish()
        terminated.commit([eos])
        terminated.finish()
        assert terminated.matcher.is_accepting()
    invalid = factory.create(grammar)
    for simulation in [[QWEN.vocabulary], [tokens[0], QWEN.vocabulary, 1],
                       tokenizer.encode("incorrect", add_special_tokens=False)[:8]]:
        masks = invalid.masks(simulation)
        steps.insert(0, {"committed": [], "simulation": simulation,
                         "maskSHA256": hashlib.sha256(masks).hexdigest()})
    result.append({"name": name, "grammar": grammar, "type": "lark" if isinstance(grammar, str) and grammar.startswith("%llguidance") else "llguidance",
                   "output": output, "tokens": tokens, "steps": steps})
import struct
vocabulary = []
for token in range(QWEN.vocabulary):
    value = factory.tokenizer.decode_bytes([token])
    if factory.tokenizer.is_special_token(token):
        value = b'\xff' + value
    vocabulary.append(value)
lengths = b''.join(struct.pack('<I', len(x)) for x in vocabulary)
vocabulary_hash = hashlib.sha256(lengths + b''.join(vocabulary)).hexdigest()
text = json.dumps({"schemaVersion": 1, "splashCommit": pin["commit"], "llguidance": "1.8.0", "byteVocabularySHA256": vocabulary_hash, "cases": result}, ensure_ascii=False, indent=2) + "\n"
path = ROOT / "IntegrationTests/Grammar/fixtures.json"
if args.write:
    path.write_text(text)
elif path.read_text() != text:
    raise RuntimeError("Native grammar reference fixture changed")
print(json.dumps({"cases": len(result), "maskRequests": sum(len(x["steps"]) for x in result)}))
