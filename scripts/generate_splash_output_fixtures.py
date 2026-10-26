#!/usr/bin/env python3
"""Freeze output behavior from pinned Splash; development-only Python."""
import argparse
import importlib.metadata
import json
from pathlib import Path
import random
import sys
from splash_reference_identity import verify

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("model", type=Path)
parser.add_argument("--write", action="store_true")
args = parser.parse_args()
source = verify(ROOT, args.model)
assert importlib.metadata.version("tokenizers") == "0.22.2"
assert importlib.metadata.version("transformers") == "5.15.1"
sys.path.insert(0, str(source))
from transformers import AutoTokenizer
from server.backend import CallbackStreamer
from server.chat_format import QWEN
from server.output import ReasoningSplitter, StreamingToolCallProjector
from server.tool_schema import normalize_tools

tokenizer = AutoTokenizer.from_pretrained(str(args.model.resolve()), local_files_only=True)
def encode(text):
    return tokenizer.encode(text, add_special_tokens=False)

# Every raw byte can be represented by a single BPE vocabulary item.
byte_chars = list(range(33, 127)) + list(range(161, 173)) + list(range(174, 256))
mapping = dict(zip(byte_chars, byte_chars))
for byte in range(256):
    if byte not in mapping:
        mapping[byte] = 256 + len([x for x in range(byte) if x not in byte_chars])
def raw(data):
    return [tokenizer.convert_tokens_to_ids(chr(mapping[byte])) for byte in data]

samples = [
    ("plain", encode("Inventory is 18.\n\nCost: $12.40."), []),
    ("unicode", encode("Bogotá 日本語 العربية 🧮 👩🏽‍💻 café"), []),
    ("bytewise_unicode", raw("cafe\u0301 日本語 🧮 👩🏽‍💻\r\n".encode()), []),
    ("tool_markers", encode('<think>Consider</think>\n<tool_call>\n<function=search>\n<parameter=query>\nquote\n</parameter>\n</function>\n</tool_call>'), []),
    ("special_tokens", encode("before<|im_start|><|im_end|><|endoftext|>after<|image_pad|>"), []),
    ("padded_tokens", encode("before") + [248319] + encode("after"), []),
    ("unfinished_utf8", raw(b"ok\xf0\x9f"), []),
    ("invalid_utf8", raw(b"\xff\xc0\xaf\xed\xa0\x80\xe0\x80\xaf\xf4\x90\x80\x80END"), []),
    ("replacement_middle", raw("A\ufffdB".encode()), []),
    ("replacement_end", raw("A\ufffd\ufffd".encode()), []),
    ("partial_stop", raw(b"answer ST"), ["STOP"]),
    ("complete_stop", raw(b"answer STOP hidden"), ["STOP"]),
    ("overlap_stop", raw(b"answer abcdef hidden"), ["abcd", "abc"]),
    ("unicode_stop", raw("antes 🧮 después".encode()), ["🧮"]),
    ("canonical_stop", raw("cafe\u0301 end".encode()), ["café"]),
    ("empty", [], []),
]
rng = random.Random(42)
for i in range(48):
    samples.append((f"bytes_{i}", raw(bytes(rng.randrange(256) for _ in range(96))), []))
for i in range(16):
    samples.append((f"tokens_{i}", [rng.randrange(248320) for _ in range(64)], []))

cases = []
for name, tokens, stops in samples:
    emitted = []
    stream = CallbackStreamer(tokenizer, emitted.append, stop_sequences=stops)
    deltas = []
    for token in tokens:
        start = len(emitted)
        stream.put_tokens([token])
        deltas.append("".join(emitted[start:]))
    start = len(emitted)
    stream.end()
    cases.append(dict(name=name, tokens=tokens, stops=stops, deltas=deltas,
                      tail="".join(emitted[start:]), output="".join(emitted), matchedStop=stream.stop_sequence))
parameters = {
    "query": ["string"], "limit": ["integer"], "amount": ["number"], "enabled": ["boolean"],
    "metadata": ["object"], "tags": ["array"], "nothing": ["null"],
    "text_or_count": ["string", "integer"], "text_or_flag": ["string", "boolean"],
}
definitions = [{"type": "function", "function": {"name": "find_evidence", "parameters": {
    "type": "object", "properties": {k: {"type": v if len(v) > 1 else v[0]} for k, v in parameters.items()},
    "required": [], "additionalProperties": False}}}]
_, policy = normalize_tools(definitions, "auto", True)
def call(fields, close=True):
    return '<tool_call>\n<function=find_evidence>\n' + ''.join(
        f'<parameter={k}>\n{v}\n</parameter>\n' for k, v in fields) + '</function>\n' + ('</tool_call>' if close else '')
one = call([("query", "invoice 1042"), ("limit", "4")])
output_samples = [
    ("plain", "A plain answer.\n", False, False, True),
    ("no_tools", one, False, False, False),
    ("one_call", one, False, False, True),
    ("empty_parameter", call([("query", "")]), False, False, True),
    ("two_calls", one + '\n\n' + call([("query", "supplier quote")]), False, False, True),
    ("framing", ' \n' + one + '\n \t', False, False, True),
    ("text_call_text", 'Looking.\n' + one + '\n\nFound it.', False, False, True),
    ("no_outer_close", call([("query", "quote")], False), False, False, True),
    ("typed", call([("amount", "1.25"), ("limit", "-2"), ("enabled", "true"),
       ("metadata", '{"name":"Bogotá 🧮","flag":false}'), ("tags", '["a",2,null]'), ("nothing", "null")]), False, False, True),
    ("python_literals", call([("enabled", "True"), ("nothing", "None")]), False, False, True),
    ("python_false", call([("enabled", "False")]), False, False, True),
    ("string_literals", call([("query", '"true"\nFalse\n1.25')]), False, False, True),
    ("union_integer", call([("text_or_count", "1")]), False, False, True),
    ("union_float", call([("text_or_count", "1.0")]), False, False, True),
    ("union_boolean", call([("text_or_flag", "true")]), False, False, True),
    ("union_python", call([("text_or_flag", "True")]), False, False, True),
    ("union_quoted", call([("text_or_count", '"quote"')]), False, False, True),
    ("embedded_tags", call([("query", 'literal\n</parameter>\nordinary text </think> <tool_call>')]), False, False, True),
    ("unicode_argument", call([("query", 'cafe\u0301 日本語 👩🏽‍💻\nquote \\"')]), False, False, True),
    ("thinking_answer", 'Check the stock.</think>\n\n18 units.', True, False, True),
    ("thinking_tool", 'Look for evidence.' + one, True, False, True),
    ("thinking_explicit_tool", 'Look.</think>\n\n' + one, True, False, True),
    ("reasoning_open", 'Still considering <tool_', True, False, True),
    ("stray_think", '</think>Ready.</think>', False, False, True),
    ("structured_markers", '{"text":"</think> <tool_call>\\n<function=find_evidence>"}', False, True, True),
    ("structured_tool", one, False, True, True),
    ("bare_tool_text", 'Literal <tool_call> in prose.', False, False, True),
    ("partial_tag_text", 'Literal <tool_', False, False, True),
    ("whitespace", '\n \t', False, False, True),
    ("no_tools_thinking", 'Think.</think>\nAnswer.', True, False, False),
    ("empty", '', False, False, True),
]
projections = []
for name, output, thinking, structured, has_tools in output_samples:
    splitter = ReasoningSplitter(thinking, tool_calls=has_tools, chat_format=QWEN)
    projector = StreamingToolCallProjector(policy if has_tools else None, 'fixture', structured, QWEN.call_syntax)
    reasoning = []
    def accept(parts):
        for kind, text in parts:
            if kind == 'reasoning_content':
                reasoning.append(text)
            else:
                projector.put(text)
    for char in output:
        accept(splitter.put(char))
    accept(splitter.finish())
    content, calls_out, _ = projector.finish(False)
    projections.append(dict(name=name, output=output, thinking=thinking, structured=structured, tools=has_tools,
                            text=content, reasoning=''.join(reasoning), calls=[
        dict(name=c['function']['name'], arguments=json.loads(c['function']['arguments'])) for c in calls_out]))
data = dict(schemaVersion=1, upstreamCommit="1744cfafee415fb463b289449cec59a864e768e9",
            tokenizers="0.22.2", transformers="5.15.1", decoders=cases,
            tools=[dict(name='find_evidence', parameters=parameters)], projections=projections)
path = ROOT / "IntegrationTests/Text/output-fixtures.json"
text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
if args.write:
    path.write_text(text)
elif path.read_text() != text:
    raise RuntimeError("Pinned reference output fixtures changed")
print(json.dumps({"decoderCases": len(cases), "projectionCases": len(projections)}))
