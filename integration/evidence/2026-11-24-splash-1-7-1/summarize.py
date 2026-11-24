"""Totals over every engine.request event in a chat timing log."""
import json, sys
for path in sys.argv[1:]:
    recs = [json.loads(l) for l in open(path)]
    reqs = [e for r in recs for e in r.get('events', []) if e.get('name') == 'engine.request']
    turns = [r for r in recs if any(e.get('name') == 'turn.begin' for e in r.get('events', []))]
    s = lambda k: sum(e.get(k) or 0 for e in reqs)
    gen, dec, cyc = s('generatedTokens'), s('decodeSeconds'), s('cycles')
    print(path.rsplit('/', 1)[-1])
    print(f"  requests {len(reqs)}  generated {gen}  decode {dec:.2f}s  -> {gen/dec:.1f} tokens/s")
    print(f"  cycles {cyc}  tokens/cycle {gen/cyc:.2f}  ms/cycle {1000*dec/cyc:.1f}  drafted {s('draftedTokens')} accepted {s('acceptedDraftTokens')}")
    print(f"  first token mean {s('firstTokenAfter')/len(reqs):.2f}s  prefill {s('prefillSeconds'):.2f}s for {s('computedTokens')} computed tokens")
    print(f"  host masks {s('masks')} in {s('maskSeconds'):.2f}s ({1000*s('maskSeconds')/max(1,s('masks')):.2f} ms each)  engine wall {s('engineWallSeconds'):.2f}s")
