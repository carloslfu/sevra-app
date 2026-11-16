#!/usr/bin/env python3
"""Qualify two retained fresh cohorts; never repair or execute generated source."""
import hashlib
import datetime
import decimal
import math
import json
import pathlib
import re
import sqlite3
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile
from check_native_app_authoring import evidence_sources

ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'integration/fixtures/excel-business'
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_package_identity(path, result, check):
    require(digest(path) == result['digest'] == check['digest'] == check['review']['digest'],
            'Exported package differs from the model publication and executed review: ' + path.name)


def require_completion(journey):
    completion = journey.get('completion', {})
    require(completion.get('unresolvedActionFailure') is False
            and completion.get('arguments', {}).get('basis') == 'completed_action'
            and isinstance(journey.get('answer'), str) and bool(journey['answer'].strip()),
            'A saved journey did not report successful completion')


def require_saved_effect(before, after, expected, formulas):
    """Check requested input values independently of the formula-output oracle."""
    require(isinstance(expected, dict) and set(expected) == {'sheet', 'match', 'values'}
            and type(expected['sheet']) is int and isinstance(before, list)
            and isinstance(after, list) and len(before) == len(after)
            and 0 <= expected['sheet'] < len(after)
            and isinstance(expected['match'], dict) and bool(expected['match'])
            and isinstance(expected['values'], dict) and bool(expected['values']),
            'Missing or invalid independent saved-effect expectation')
    target = expected['sheet']
    def matches(row):
        return all(row.get(k) == v for k, v in expected['match'].items())
    def spelling(value):
        if not isinstance(value, str) or len(value.encode()) > 256 or not re.fullmatch(
                r'-?(0|[1-9][0-9]*)(\.[0-9]+)?', value):
            return None
        return value.rstrip('0').rstrip('.') if '.' in value else value
    rows = [r for r in after[target] if matches(r)]
    require(len(rows) == 1, 'Expected exactly one saved business record')
    for column, value in expected['values'].items():
        actual = rows[0].get(column)
        require(actual == value or (spelling(actual) is not None
                                   and spelling(actual) == spelling(value)),
                'Wrong saved business input: ' + column)
    require(after != before, 'No saved change after the requested operation')
    for sheet, prior in enumerate(before):
        current = after[sheet]
        require(len(current) == len(prior) or (sheet == target and len(current) == len(prior) + 1),
                'Unexpected row insertion, removal or replacement')
        for position, row in enumerate(prior):
            is_target = sheet == target and matches(current[position])
            for column, old in row.items():
                require(re.fullmatch(r'c[1-9][0-9]*', column) is not None, 'Invalid worksheet column')
                if (sheet, position, int(column[1:]) - 1) in formulas:
                    continue
                require((is_target and column in expected['values']) or current[position].get(column) == old,
                        'Unrelated business input changed')


def asserted_successful_actions(steps):
    return {call['action'] for call, assertion in zip(steps, steps[1:])
            if call.get('kind') == 'run_action' and call.get('error') is None
            and call.get('reject') is None and call.get('action')
            and ((assertion.get('kind') in ['expect_row', 'expect_rows']
                  and isinstance(assertion.get('values'), dict) and assertion['values'])
                 or assertion.get('kind') in ['expect_value', 'expect_text'])}


def number_variants(role, value):
    require(isinstance(role, dict) and set(role) == {'kind', 'whole', 'minimum', 'maximum', 'nonzero'}
            and role['kind'] == 'number' and type(role['whole']) is bool
            and type(role['nonzero']) is bool, 'Invalid numeric classification')
    with decimal.localcontext() as context:
        context.prec = 38
        def number(raw, bound=False):
            require(type(raw) in ([int, float] if bound else [int, float, str]), 'Invalid numeric value')
            try:
                result = decimal.Decimal(str(raw))
            except decimal.InvalidOperation as error:
                raise ValueError('Invalid numeric value') from error
            require(result.is_finite(), 'Nonfinite numeric value')
            return result
        base = number(value)
        minimum = None if role['minimum'] is None else number(role['minimum'], True)
        maximum = None if role['maximum'] is None else number(role['maximum'], True)
        def in_range(n):
            return (minimum is None or n >= minimum) and (maximum is None or n <= maximum)
        require(in_range(base) and (not role['whole'] or base == base.to_integral_value())
                and (not role['nonzero'] or base != 0), 'Successful call violates declared numeric rules')
        variants = []
        if role['whole']:
            candidates = [base + decimal.Decimal('0.5'), base - decimal.Decimal('0.5')]
            if minimum is not None and minimum < base:
                candidates.append(base / 2 + minimum / 2)
            if maximum is not None and maximum > base:
                candidates.append(base / 2 + maximum / 2)
            fraction = next((n for n in candidates
                             if in_range(n) and n != n.to_integral_value()
                             and (not role['nonzero'] or n != 0)), None)
            if fraction is not None:
                variants.append(('whole', fraction))
            else:
                require(minimum == base == maximum, 'Cannot derive a fractional probe')
        if minimum is not None:
            lower = minimum.to_integral_value(rounding=decimal.ROUND_FLOOR) if role['whole'] else minimum - 1
            if lower == minimum:
                lower -= 1
            if role['nonzero'] and lower == 0:
                lower -= 1
            require(lower < minimum, 'Minimum probe exceeds precision')
            variants.append(('minimum', lower))
        if maximum is not None:
            upper = maximum.to_integral_value(rounding=decimal.ROUND_CEILING) if role['whole'] else maximum + 1
            if upper == maximum:
                upper += 1
            if role['nonzero'] and upper == 0:
                upper += 1
            require(upper > maximum, 'Maximum probe exceeds precision')
            variants.append(('maximum', upper))
        if role['nonzero']:
            variants.append(('nonzero', decimal.Decimal(0)))
        zero = decimal.Decimal(0)
        if base != zero and in_range(zero) and not role['nonzero']:
            variants.append(('allowed_zero', zero))
        if base != zero and base == base.to_integral_value() and not role['whole']:
            half = decimal.Decimal('0.5')
            fraction = base - half if base > zero else base + half
            if in_range(fraction) and fraction != fraction.to_integral_value():
                variants.append(('allowed_fraction', fraction))
        def typed(n):
            if isinstance(value, str):
                text = format(n, 'f')
                return text.rstrip('0').rstrip('.') if '.' in text else text
            result = float(n)
            return result
        typed_variants = []
        for rule, n in variants:
            sample = typed(n)
            if not isinstance(value, str) and (not math.isfinite(sample) or number(sample) != n):
                if rule in {'allowed_zero', 'allowed_fraction'}:
                    continue
                raise ValueError('Numeric probe cannot be represented exactly')
            typed_variants.append((rule, sample))
        return typed_variants


def require_input_checks(probe, package_digest):
    """Verify declared numeric/key rules got the host-derived probes and passed."""
    steps = probe['tests']
    roles = probe.get('inputRoles')
    require(isinstance(roles, dict) and set(roles) <= asserted_successful_actions(steps),
            'Missing successful calls for classified inputs')
    for index in range(len(steps) - 1):
        if not asserted_successful_actions(steps[index:index + 2]):
            continue
        following = []
        for assertion in steps[index + 1:]:
            if assertion.get('kind') not in ['expect_row', 'expect_rows', 'expect_text', 'expect_value']:
                break
            following.append(assertion)
        if any(assertion.get('kind') in ['expect_row', 'expect_rows'] for assertion in following):
            changes = probe.get('check', {}).get('actionChanges', {}).get(str(index))
            require(type(changes) is int and changes > 0, 'Successful saved effect did not commit a write')
    expected = {}
    for action, fields in roles.items():
        index = next(i for i in range(len(steps) - 1)
                     if action in asserted_successful_actions(steps[i:i + 2]))
        call = steps[index]
        require(isinstance(fields, dict) and set(fields) == set(call.get('inputs', {})),
                'Incomplete action input classification')
        variants = []
        for field, role in sorted(fields.items()):
            kind = probe.get('check', {}).get('actionInputTypes', {}).get(str(index), {}).get(field)
            require(kind in ['text', 'number', 'decimal', 'boolean', 'record', 'date'], 'Missing executed input type')
            if role == {'kind': 'value'}:
                require(kind not in ['number', 'decimal'], 'Numeric input hidden as value')
                continue
            if isinstance(role, dict) and role.get('kind') == 'number':
                require(kind in ['number', 'decimal'], 'Numeric role on nonnumeric input')
                variants += [{'input': field, 'rule': rule, 'value': value}
                             for rule, value in number_variants(role, call['inputs'][field])]
                continue
            require(isinstance(role, dict) and role.get('kind') == 'existingKey'
                    and set(role) == {'kind', 'table', 'column', 'headerRow'},
                    'Invalid existing-key classification')
            require(type(role['headerRow']) is int and role['headerRow'] > 0
                    and isinstance(role['table'], str) and role['table']
                    and isinstance(role['column'], str) and role['column'], 'Invalid key coordinates')
            if kind in ['number', 'decimal', 'boolean']:
                continue  # Successful SDK type checks prevent a text header reaching this input.
            require(isinstance(call['inputs'][field], str), 'Invalid key input type')
            variants.append({'input': field, 'rule': 'header'})
        for variant in variants:
            expected[action, variant['input'], variant['rule']] = (index, call, variant)
    checks = probe.get('inputChecks')
    require(isinstance(checks, list) and len(checks) == len(expected)
            and {(p.get('action'), p.get('input'), p.get('rule')) for p in checks} == set(expected),
            'Missing or duplicate automatic input checks')
    for check in checks:
        index, call, want = expected[check['action'], check['input'], check['rule']]
        if want['rule'] == 'header':
            require(isinstance(check.get('value'), str) and bool(check['value'])
                    and isinstance(check.get('cell'), str) and bool(check['cell']), 'Missing original-header evidence')
            want = {**want, 'value': check['value'], 'cell': check['cell']}
        require(check.get('controlInputs') == call['inputs'],
                'Derived input variant does not preserve the successful control')
        actual = {k: v for k, v in check.items()
                  if k not in ['action', 'tests', 'check', 'controlInputs']}
        require(actual == want, 'Derived input variant does not match declared rules')
        changed = {**call, 'inputs': {**call['inputs'], check['input']: check['value']}}
        allowed = want['rule'] in {'allowed_zero', 'allowed_fraction'}
        if not allowed:
            changed['reject'] = True
        require(check['tests'] == steps[:index] + [changed],
                'Each input variant must preserve exactly the prior setup and run in its own check')
        require(check['check']['status'] == 'passed' and check['check']['digest'] == package_digest,
                'Input check failed or checked a different package')
        if allowed:
            assertions = check['check'].get('assertions')
            changes = check['check'].get('actionChanges', {}).get(str(index))
            require(type(assertions) is int and assertions > 0 and type(changes) is int and changes >= 0,
                    'Allowed-input probe did not complete its final action')
    return set(roles)


def require_consecutive(directories, runtimes):
    require(directories[0].parent == directories[1].parent,
            'Keep cohorts in one retained trial directory so intervening failures are visible')

    def interval(runtime):
        start = datetime.datetime.fromisoformat(runtime['startedAt'])
        end = datetime.datetime.fromisoformat(runtime['finishedAt'])
        require(start.tzinfo is not None and end.tzinfo is not None and start <= end,
                'Invalid cohort time interval')
        return start, end

    first, second = map(interval, runtimes)
    require(first[1] <= second[0], 'Cohorts must run consecutively without overlap')
    for receipt in directories[0].parent.glob('*/runtime.json'):
        if receipt.parent in directories:
            continue
        other = read(receipt)
        if 'integration/fixtures/excel-business/cases.json' not in other.get('fixtures', {}):
            continue
        start, end = interval(other)
        require(end <= first[0] or start >= second[1],
                'Another business trial intervened or overlapped: ' + receipt.parent.name)


def formula_positions(path):
    with zipfile.ZipFile(path) as archive:
        workbook = ET.fromstring(archive.read('xl/workbook.xml'))
        rels = {node.attrib['Id']: node.attrib['Target'] for node in ET.fromstring(
            archive.read('xl/_rels/workbook.xml.rels'))}
        positions = set()
        for index, sheet in enumerate(workbook.findall('s:sheets/s:sheet', NS)):
            target = rels[sheet.attrib['{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id']]
            target = target.lstrip('/') if target.startswith('/') else 'xl/' + target
            for cell in ET.fromstring(archive.read(target)).findall('.//s:c', NS):
                if cell.find('s:f', NS) is None:
                    continue
                address = cell.attrib['r']
                letters = ''.join(c for c in address if c.isalpha())
                column = 0
                for letter in letters:
                    column = column * 26 + ord(letter) - 64
                positions.add((index, int(address[len(letters):]) - 1, column - 1))
        return positions


def qualify(directory, cases, invalid):
    runtime = read(directory / 'runtime.json')
    require(runtime.get('sourceUnchangedAtEnd') is True, 'Code changed during cohort: ' + str(directory))
    require(set(runtime['sources']) == {str(p.relative_to(ROOT)) for p in evidence_sources()},
            'Incomplete source identity inventory')
    require(set(runtime['fixtures']) == {str(p.relative_to(ROOT)) for p in FIXTURES.iterdir() if p.is_file()},
            'Incomplete fixture identity inventory')
    for group in ['sources', 'fixtures']:
        for name, expected in runtime[group].items():
            require((ROOT / name).is_file() and digest(ROOT / name) == expected,
                    'Cohort differs from current ' + name)
    results = read(directory / 'results.json')
    require(len(results) == len(cases) and {r['slug'] for r in results} == set(cases),
            'The complete six-app cohort is required')
    subprocess.run([sys.executable, str(ROOT / 'scripts/verify_excel_business_oracles.py'),
                    str(directory)], check=True, stdout=subprocess.DEVNULL)
    oracle = read(directory / 'oracle-verification.json')
    manifest = read(directory / 'oracle-manifest.json')
    require(oracle['passed'], 'Independent spreadsheet comparison failed')
    summary = []
    for result in results:
        slug = result['slug']
        case = cases[slug]
        require(all(result.get(key) is True for key in [
            'passed', 'freshModelTrial', 'heldoutPassed', 'unchangedSourceRebuildPassed']),
            'Incomplete fresh application: ' + slug)
        require(result['invalidDirectCases'] == sum(len(rule['values'])
                for group in invalid[slug] for rule in group['invalid']), 'Missing refusals: ' + slug)
        require(result.get('invalidRecoveryCases') == result['invalidDirectCases'],
                'Missing valid correction after each invalid input: ' + slug)
        expected_steps = list(range(len(case['journeys']))) + ['undo']
        for index in range(len(invalid[slug])):
            expected_steps += [f'validation-control-{index}', f'validation-undo-{index}']
        if slug == 'stock':
            require(result.get('pagedGrowthRecords') == 205, 'Missing stock pagination challenge')
            expected_steps.append('paged-growth')
        journeys = read(directory / (slug + '-journeys.json'))
        for step, expected in enumerate(case['journeys']):
            if not expected.get('unchanged', False):
                observed = next((j for j in journeys if j['step'] == step), {})
                require_completion(observed)
        scenarios = [s for s in manifest if s['slug'] == slug]
        require(len(journeys) == len(expected_steps) == len(scenarios)
                and {str(j['step']) for j in journeys} == {str(s) for s in expected_steps}
                and {str(s['step']) for s in scenarios} == {str(s) for s in expected_steps},
                'Missing or duplicate journey/oracle state: ' + slug)
        positions = formula_positions(FIXTURES / case['files'][0])
        require(bool(positions), 'Corpus must contain formulas: ' + slug)
        states = {str(j['step']): j['state'] for j in journeys}
        baseline = states['paged-growth' if slug == 'stock' else 'undo']
        for index, group in enumerate(invalid[slug]):
            require_saved_effect(baseline, states[f'validation-control-{index}'], group.get('expected'), positions)
            require(states[f'validation-undo-{index}'] == baseline, 'Control Undo changed business inputs')
        for scenario in scenarios:
            require(len(scenario['outputs']) == len(positions) and {
                (o['sheet'], o['row'], o['column']) for o in scenario['outputs']} == positions,
                'Oracle omitted or duplicated formula outputs: ' + slug)
            state = next(j['state'] for j in journeys if j['step'] == scenario['step'])
            require(all(state[o['sheet']][o['row']]['c' + str(o['column'] + 1)] == o['actual']
                        for o in scenario['outputs']), 'Oracle used a different saved state: ' + slug)
        package = read(directory / (slug + '.sevraapp'))
        connection = sqlite3.connect((directory / (slug + '.sevra') / 'workbook.sqlite').as_uri()
                                     + '?mode=ro', uri=True)
        try:
            calls = connection.execute("SELECT arguments,result,state FROM tool_calls "
                                       "WHERE tool='save_native_app' ORDER BY created").fetchall()
            saved = [(json.loads(a), json.loads(r)) for a, r, state in calls
                     if state == 'completed' and json.loads(r).get('status') == 'saved_disabled']
            require(len(saved) == 1, 'Expected one model publication: ' + slug)
            require(saved[0][0]['package']['source'] == package['source'],
                    'Generated source was changed after its model submission: ' + slug)
            require(saved[0][1]['check']['review']['decision'] == 'ready', 'Missing local review: ' + slug)
            require(saved[0][1]['check']['review'].get('method') == 'contract-probes',
                    'Independent review must withhold the candidate implementation: ' + slug)
            check = saved[0][1]['check']
            require_package_identity(directory / (slug + '.sevraapp'), result, check)
            readiness = check['review']['independentActionCheck']
            require(bool(check['actions']) and set(readiness['actions']) == set(check['actions'])
                    and bool(readiness['checks'])
                    and all(probe['check']['status'] == 'passed' for probe in readiness['checks'])
                    and set().union(*(asserted_successful_actions(probe['tests'])
                                      for probe in readiness['checks'])) >= set(check['actions']),
                    'Missing executed independent action probes: ' + slug)
            require(set().union(*(require_input_checks(probe, check['digest'])
                                  for probe in readiness['checks'])) == set(check['actions']),
                    'Missing independent input classifications: ' + slug)
            models = [m[0] for m in connection.execute('SELECT DISTINCT model FROM agent_runs')]
            require(len(models) == 1 and models[0].startswith('Splash '), 'Unexpected model: ' + slug)
        finally:
            connection.close()
        require((directory / (slug + '.sevraz')).is_file(), 'Missing portable copy: ' + slug)
        summary.append({'slug': slug, 'generationSeconds': result['generationSeconds'],
                        'totalSeconds': result['seconds'], 'saveAttempts': len(calls),
                        'invalidCases': result['invalidDirectCases'], 'model': models[0]})
    return runtime, {'directory': directory.name, 'applications': summary,
                     'oracleScenarios': oracle['scenarios'],
                     'formulaComparisons': oracle['formulaComparisons']}


def main():
    require(len(sys.argv) == 3, 'Supply two consecutive complete cohort directories')
    directories = [pathlib.Path(p).resolve() for p in sys.argv[1:]]
    require(directories[0] != directories[1], 'Two distinct fresh cohorts are required')
    cases = {case['slug']: case for case in read(FIXTURES / 'cases.json')}
    invalid = read(FIXTURES / 'adversarial.json')
    cohorts = [qualify(directory, cases, invalid) for directory in directories]
    first, second = [c[0] for c in cohorts]
    require_consecutive(directories, [first, second])
    for key in ['sources', 'fixtures', 'buildProducts', 'resources', 'engineSHA256', 'guidanceSHA256']:
        require(first[key] == second[key], 'Cohort runtime changed: ' + key)
    require(len({app['model'] for _, cohort in cohorts for app in cohort['applications']}) == 1,
            'Cohorts used different model configurations')
    print(json.dumps({'passed': True, 'cohorts': [c[1] for c in cohorts]}, indent=2))


if __name__ == '__main__':
    main()
