"""Development-only worker around the unchanged pinned Splash frontend/backend.

No HTTP listener. JSON stdin/stdout is benchmark orchestration, not a product API.
"""
import copy
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


def required_first(value):
    if isinstance(value, list):
        return [required_first(v) for v in value]
    if not isinstance(value, dict):
        return value
    result = {k: required_first(v) for k, v in value.items()}
    if 'properties' in result:
        props = result['properties']
        names = [k for k in result.get('required', []) if k in props]
        names += sorted(k for k in props if k not in names)
        result['properties'] = {k: props[k] for k in names}
    return result


def workbook_grammar(grammar):
    """Apply the workbook's nested property order without changing its prompt."""
    if grammar.startswith('{'):
        container = json.loads(grammar)
        for item in container['grammars']:
            item['lark_grammar'] = workbook_grammar(item['lark_grammar'])
        return json.dumps(container, separators=(',', ':'))
    decoder = json.JSONDecoder()
    pieces = []
    remaining = grammar
    while '%json ' in remaining:
        prefix, remaining = remaining.split('%json ', 1)
        schema, end = decoder.raw_decode(remaining)
        pieces.append(prefix + '%json ' + json.dumps(required_first(schema), separators=(',', ':')))
        remaining = remaining[end:]
    return ''.join(pieces) + remaining


def main():
    import os
    import base64
    import dataclasses
    config = json.loads(Path(sys.argv[1]).read_text())
    from splash_reference_identity import verify
    sys.path.insert(0, str(verify(ROOT, Path(config['assembly']) / 'tokenizer')))
    began = time.monotonic()
    from transformers import AutoTokenizer
    from server.backend import NativeBackend
    from server.chat_format import QWEN
    from server.chat_templates import ChatTemplates
    from server.constraints import ConstraintFactory, validate_tokenizer
    from server.frontend import Frontend
    from server.runtime import MultiplexedRuntime
    from server.server import FrontendHandler
    from server.thinking import ThinkingCodec
    from server import protocol as wire

    class WorkbookConstraintFactory(ConstraintFactory):
        def create(self, grammar, **kwargs):
            # Match Sevra's declared nested schema order only at the grammar
            # boundary. Reordering the request also changes its chat prompt.
            return super().create(workbook_grammar(grammar), **kwargs)

    class ObservedBackend(NativeBackend):
        # Observation only; all preparation, admission, masks, decoding,
        # finalization and tool validation remain upstream code.
        def _generation_request(self, job):
            request = super()._generation_request(job)
            if config.get('workflowQualification'):
                frame = dataclasses.replace(request.frame, request_id=1,
                    absolute_deadline_unix_micros=1, remaining_deadline_micros=180_000_000)
                self.request_frame = base64.b64encode(wire.serialize_message(frame)).decode('ascii')
            return request

        def _on_event(self, state, event):
            if isinstance(event, wire.TokensEvent):
                if self.first_token is None:
                    self.first_token = time.monotonic()
                self.tokens.extend(event.tokens)
            return super()._on_event(state, event)

    class Collector:
        _collect = FrontendHandler._collect
        _finalize_content = FrontendHandler._finalize_content

        def _next_event(self, job, on_idle=None):
            kind, value = job.events.get(timeout=max(0.001, job.deadline - time.monotonic()))
            if kind == 'error':
                raise value
            return kind, value

    tokenizer = AutoTokenizer.from_pretrained(
        str(Path(config['assembly']) / 'tokenizer'), local_files_only=True, trust_remote_code=False)
    validate_tokenizer(tokenizer, QWEN)
    templates = ChatTemplates(tokenizer)
    runtime = MultiplexedRuntime([
        config['engine'], 'serve-native', config['assembly'], str(config['contextTokens']),
        str(config['memoryBytes']), '--persistent-cache', 'off', '--idle-sleep', 'allow',
        '--verify-rows', 'all'], startup_timeout=180, pending_limit=64)
    backend = ObservedBackend(runtime, tokenizer, request_logger=lambda *args, **kw: None)
    try:
        runtime.wait_ready()
        frontend = Frontend(tokenizer, backend, 'benchmark', config['contextTokens'], 180, 1,
            constraint_factory=WorkbookConstraintFactory(tokenizer, QWEN), chat_templates=templates,
            chat_format=QWEN, thinking_codec=ThinkingCodec(), vision=False)
        emit({'ready': True, 'pid': os.getpid(), 'helperPID': runtime._process.pid,
              'setupSeconds': time.monotonic() - began})
        for line in sys.stdin:
            command = json.loads(line)
            if command.get('op') == 'close':
                backend.close()
                emit({'closed': True})
                break
            index = command.get('case', -1)
            # Development-only whole-workbook harness supplies the live host
            # envelope. The frozen R1 case path remains unchanged.
            case = ({'id': command['id'], 'body': command['body']}
                    if command.get('op') == 'workflow' else config['cases'][index])
            body = copy.deepcopy(case['body'])
            started = time.monotonic()
            job = frontend.prepare(body, deadline=started + 180)
            if command.get('op') == 'workflow' and len(job.prompt_tokens) > 24000:
                raise ValueError('Workflow qualification exceeds its declared 24000-token prompt bound')
            prepared = time.monotonic()
            backend.tokens, backend.first_token = [], None
            backend.submit(job)
            collected = Collector()._collect(job)
            elapsed = time.monotonic() - started
            result = collected.result
            calls = [{'name': c['function']['name'],
                      'arguments': json.loads(c['function']['arguments'])}
                     for c in collected.tool_calls]
            emit({'case': index, 'id': case['id'], 'completeSeconds': elapsed,
                  'prepareSeconds': prepared - started,
                  'firstTokenSeconds': None if backend.first_token is None else backend.first_token - started,
                  'engineRequestSeconds': result.request_wall_ms / 1000,
                  'prefillSeconds': result.start_to_first_token_ms / 1000,
                  'decodeSeconds': result.first_token_to_done_ms / 1000,
                  'promptTokens': job.prompt_tokens, 'generationTokens': job.generation_prompt_tokens,
                  'matchedPromptTokens': result.cache.matched_tokens,
                  'tokens': backend.tokens, 'text': collected.content,
                  **({'requestFrame': backend.request_frame} if config.get('workflowQualification') else {}),
                  'reasoning': collected.reasoning, 'calls': calls,
                  'finish': {'stop': 0, 'length': 1, 'cancelled': 2}[result.reason],
                  'bounded': result.bounded, 'drafted': result.drafted_tokens,
                  'accepted': result.accepted_draft_tokens, 'status': backend.status()})
    finally:
        backend.close()


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        emit({'error': str(error)})
        raise
