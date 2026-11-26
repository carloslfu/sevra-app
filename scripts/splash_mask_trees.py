"""Draft trees for the reference mask fixtures, built with pinned Splash reference Python only.

Splash 1.7.3 sends a verify block's draft as a tree: each token's parent is an earlier
token, and the first token's is NO_PARENT. A fixture step holds the committed tokens, the
draft tokens and their parents, the hash of the reference masks and the reference's forced
pairs (kept for later use; the app returns none yet).
"""
import hashlib

import numpy


def chain(tokens, no_parent):
    """Parents of a draft chain: each token follows the one before it."""
    return [no_parent if index == 0 else index - 1 for index in range(len(tokens))]


def step(constraint, committed, simulation, parents):
    masks, forced = constraint.masks(tuple(simulation), tuple(parents))
    return {'committed': list(committed), 'simulation': list(simulation), 'parents': list(parents),
            'maskSHA256': hashlib.sha256(masks).hexdigest(), 'forced': list(forced)}


def allowed_after(factory, grammar, committed):
    """The tokens the grammar admits after `committed`, from a fresh constraint's row 0."""
    probe = factory.create(grammar)
    probe.commit(list(committed))
    masks, _ = probe.masks((), ())
    words = numpy.frombuffer(masks, dtype='<u4')
    bits = numpy.unpackbits(words.view(numpy.uint8), bitorder='little')
    return set(numpy.flatnonzero(bits).tolist())


def tree(factory, grammar, tokens, offset, ready, no_parent):
    """One draft tree at `offset`: the output's next tokens as a chain from its root, a stop
    token below the chain's second token, and below the root a token the grammar admits there
    and one it refuses. None when the output has no token left."""
    path = tokens[offset:offset + 3]
    if not path:
        return None
    stops = set(ready.stop_token_ids)
    allowed = allowed_after(factory, grammar, tokens[:offset + 1])
    taken = set(path[1:2])
    valid = next((t for t in sorted(allowed) if t not in stops and t not in taken), None)
    refused = next(t for t in range(ready.vocabulary_size) if t not in allowed and t not in stops)
    simulation, parents = [path[0]], [no_parent]
    if len(path) > 1:
        simulation.append(path[1])
        parents.append(0)
    if len(path) > 2:
        simulation.append(path[2])
        parents.append(1)
    if len(path) > 1:
        simulation.append(ready.stop_token_ids[-1])
        parents.append(1)
    for token in ([valid] if valid is not None else []) + [refused]:
        simulation.append(token)
        parents.append(0)
    if len(path) == 1:
        simulation.append(ready.stop_token_ids[-1])
        parents.append(0)
    return simulation, parents
