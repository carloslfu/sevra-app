"""An intervening failed trial cannot be hidden by selecting two passing cohorts."""
import json
import hashlib
import copy
from pathlib import Path
import tempfile
from qualify_excel_business import require_consecutive, require_package_identity, asserted_successful_actions, require_input_checks, number_variants, require_completion, require_saved_effect


before_effect = [[{'c1': 'R1', 'c2': '2', 'c3': '4'}, {'c1': 'R2', 'c2': '3', 'c3': '6'}]]
after_effect = [[{'c1': 'R1', 'c2': '1.50', 'c3': '3'}, {'c1': 'R2', 'c2': '3', 'c3': '6'}]]
expected_effect = {'sheet': 0, 'match': {'c1': 'R1'}, 'values': {'c2': '1.5'}}
formulas_effect = {(0, 0, 2), (0, 1, 2)}
require_saved_effect(before_effect, after_effect, expected_effect, formulas_effect)
for fault in ['coerced', 'substituted', 'unrelated', 'extra_row', 'missing', 'no_change']:
    altered = copy.deepcopy(after_effect)
    if fault == 'coerced': altered[0][0]['c2'] = '1'
    if fault == 'substituted': altered[0][0]['c2'] = '1.50000000000001'
    if fault == 'unrelated': altered[0][1]['c2'] = '4'
    if fault == 'extra_row': altered[0] += [{'c1': 'R3'}, {'c1': 'R4'}]
    if fault == 'missing': altered[0][0]['c1'] = 'R0'
    if fault == 'no_change': altered = before_effect
    try:
        require_saved_effect(before_effect, altered, expected_effect, formulas_effect)
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid saved input effect passed: ' + fault)
print('PASS valid-control effects: exact inputs and unrelated records checked independently of formula outputs')


completed = {'answer': 'Saved the loan update.', 'completion': {
    'unresolvedActionFailure': False, 'arguments': {'basis': 'completed_action'}}}
require_completion(completed)
for fault in ['stale_failure', 'missing', 'unresolved', 'blank']:
    malformed = copy.deepcopy(completed)
    if fault == 'stale_failure': malformed['completion']['unresolvedActionFailure'] = True
    if fault == 'missing': del malformed['completion']['unresolvedActionFailure']
    if fault == 'unresolved': malformed['completion']['arguments']['basis'] = 'unresolved'
    if fault == 'blank': malformed['answer'] = ' '
    try:
        require_completion(malformed)
    except ValueError:
        pass
    else:
        raise AssertionError('An untruthful/missing completion passed: ' + fault)


call = {'kind': 'run_action', 'action': 'ship', 'inputs': {'amount': '3'}}
assertion = {'kind': 'expect_row', 'table': 'ledger', 'values': {'amount': '-3'}}
assert asserted_successful_actions([call, assertion]) == {'ship'}
for steps in [
    [{**call, 'reject': True}, assertion],
    [{**call, 'error': 'Expected refusal'}, assertion],
    [call, {'kind': 'expect_rows', 'table': 'ledger', 'count': 1}],
    [assertion, call],
    [call, {'kind': 'expect_control', 'target': 'Ship'}, assertion],
]:
    assert not asserted_successful_actions(steps), 'Missing successful-effect evidence passed'

key_call = {'kind': 'run_action', 'action': 'ship', 'inputs': {'sku': 'P1', 'reference': 'R1'}}
setup = {'kind': 'expect_text', 'value': 'Ready'}
key_probe = {
    'tests': [setup, key_call, assertion],
    'check': {'actionInputTypes': {'1': {'sku': 'text', 'reference': 'text'}}, 'actionChanges': {'1': 1}},
    'inputRoles': {'ship': {'sku': {'kind': 'existingKey', 'table': 'products', 'column': 'sku',
                                  'headerRow': 1}, 'reference': {'kind': 'value'}}},
    'inputChecks': [{'action': 'ship', 'input': 'sku', 'rule': 'header', 'value': 'SKU', 'cell': 'sheet1!A1',
                   'controlInputs': dict(key_call['inputs']),
                   'tests': [setup, {**key_call, 'inputs': {'sku': 'SKU', 'reference': 'R1'}, 'reject': True}],
                   'check': {'status': 'passed', 'digest': 'package'}}],
}
assert require_input_checks(key_probe, 'package') == {'ship'}
for repeat in [False, True]:
    multiple_effects = copy.deepcopy(key_probe)
    if repeat:
        multiple_effects['tests'] += [key_call, setup, assertion]
        index = 3
    else:
        multiple_effects['tests'].insert(2, setup)
        index = 1
    multiple_effects['check']['actionChanges'][str(index)] = 1
    assert require_input_checks(multiple_effects, 'package') == {'ship'}
    multiple_effects['check']['actionChanges'][str(index)] = 0
    try:
        require_input_checks(multiple_effects, 'package')
    except ValueError as error:
        assert 'did not commit a write' in str(error)
    else:
        raise AssertionError('A leading text result or repeated action hid a no-op saved effect')
numeric_probe = copy.deepcopy(key_probe)
numeric_probe['tests'][1]['inputs']['sku'] = 42
numeric_probe['check']['actionInputTypes']['1']['sku'] = 'number'
numeric_probe['inputChecks'] = []
assert require_input_checks(numeric_probe, 'package') == {'ship'}
for fault in ['missing', 'duplicate', 'digest', 'prefix', 'header', 'roles', 'fields', 'type', 'no_write', 'missing_write',
              'wrong_control', 'missing_control']:
    malformed = copy.deepcopy(key_probe)
    if fault == 'missing': malformed['inputChecks'] = []
    if fault == 'duplicate': malformed['inputChecks'] *= 2
    if fault == 'digest': malformed['inputChecks'][0]['check']['digest'] = 'different'
    if fault == 'prefix': malformed['inputChecks'][0]['tests'].insert(1, key_call)
    if fault == 'header': malformed['inputChecks'][0]['value'] = 'different'
    if fault == 'wrong_control': malformed['inputChecks'][0]['controlInputs']['sku'] = 'R2'
    if fault == 'missing_control': del malformed['inputChecks'][0]['controlInputs']
    if fault == 'roles': malformed['inputRoles'] = None
    if fault == 'fields': del malformed['inputRoles']['ship']['reference']
    if fault == 'type': del malformed['check']['actionInputTypes']
    if fault == 'no_write': malformed['check']['actionChanges']['1'] = 0
    if fault == 'missing_write': del malformed['check']['actionChanges']
    try:
        require_input_checks(malformed, 'package')
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid existing-key proof passed: ' + fault)

number_role = {'kind': 'number', 'minimum': 1, 'maximum': 3, 'whole': True, 'nonzero': False}
assert number_variants(number_role, 1) == [('whole', 1.5), ('minimum', 0), ('maximum', 4)]
assert number_variants(number_role, '3.00') == [('whole', '2.5'), ('minimum', '0'), ('maximum', '4')]
assert number_variants({**number_role, 'maximum': 1.2}, 1) == [('whole', 1.1), ('minimum', 0), ('maximum', 2)]
assert number_variants({**number_role, 'minimum': 1.5, 'maximum': 3.25}, 2) == [('whole', 2.5), ('minimum', 1), ('maximum', 4)]
assert number_variants({**number_role, 'minimum': -3.25, 'maximum': -1.5}, -2) == [('whole', -1.5), ('minimum', -4), ('maximum', -1)]
assert number_variants({**number_role, 'nonzero': True}, 1) == [('whole', 1.5), ('minimum', -1), ('maximum', 4), ('nonzero', 0)]
unrestricted = {'kind': 'number', 'minimum': None, 'maximum': None, 'whole': False, 'nonzero': False}
assert number_variants(unrestricted, '10') == [('allowed_zero', '0'), ('allowed_fraction', '9.5')]
assert number_variants(unrestricted, -2) == [('allowed_zero', 0), ('allowed_fraction', -1.5)]
assert number_variants(unrestricted, 1e16) == [('allowed_zero', 0)]
assert number_variants(unrestricted, 0) == []
number_probe = copy.deepcopy(key_probe)
number_probe['inputRoles']['ship']['sku'] = number_role
number_probe['check']['actionInputTypes']['1']['sku'] = 'number'
number_probe['tests'][1]['inputs']['sku'] = 1
variants = [{'input': 'sku', 'rule': rule, 'value': value} for rule, value in number_variants(number_role, 1)]
number_probe['inputChecks'] = [
    {**variant, 'action': 'ship',
     'controlInputs': dict(number_probe['tests'][1]['inputs']),
     'tests': [setup, {**key_call, 'inputs': {**key_call['inputs'], 'sku': variant['value']}, 'reject': True}],
     'check': {'status': 'passed', 'digest': 'package'}} for variant in variants]
assert require_input_checks(number_probe, 'package') == {'ship'}
allowed_probe = copy.deepcopy(number_probe)
allowed_probe['inputRoles']['ship']['sku'] = unrestricted
allowed_probe['inputChecks'] = [
    {'input': 'sku', 'rule': rule, 'value': value, 'action': 'ship',
     'controlInputs': dict(allowed_probe['tests'][1]['inputs']),
     'tests': [setup, {**key_call, 'inputs': {**key_call['inputs'], 'sku': value}}],
     'check': {'status': 'passed', 'digest': 'package', 'assertions': 2, 'actionChanges': {'1': 1}}}
    for rule, value in number_variants(unrestricted, 1)]
assert require_input_checks(allowed_probe, 'package') == {'ship'}
for fault in ['missing', 'rejected', 'no_final_action']:
    malformed = copy.deepcopy(allowed_probe)
    if fault == 'missing': malformed['inputChecks'].pop(0)
    if fault == 'rejected': malformed['inputChecks'][0]['tests'][1]['reject'] = True
    if fault == 'no_final_action': malformed['inputChecks'][0]['check']['actionChanges'] = {}
    try:
        require_input_checks(malformed, 'package')
    except ValueError:
        pass
    else:
        raise AssertionError('An untested allowed input passed: ' + fault)
independent_order = copy.deepcopy(number_probe)
independent_order['inputChecks'].reverse()
assert require_input_checks(independent_order, 'package') == {'ship'}
for fault in ['hidden', 'missing', 'value', 'shared_state', 'integer']:
    malformed = copy.deepcopy(number_probe)
    if fault == 'hidden': malformed['inputRoles']['ship']['sku'] = {'kind': 'value'}
    if fault == 'missing': malformed['inputChecks'].pop()
    if fault == 'value': malformed['inputChecks'][0]['value'] = 1
    if fault == 'shared_state': malformed['inputChecks'][1]['tests'].insert(1, malformed['inputChecks'][0]['tests'][1])
    if fault == 'integer': malformed['inputRoles']['ship']['sku']['whole'] = 'true'
    try:
        require_input_checks(malformed, 'package')
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid numeric proof passed: ' + fault)


def runtime(start, end, business=True):
    return {'startedAt': f'2026-11-15T{start:02}:00:00+00:00',
            'finishedAt': f'2026-11-15T{end:02}:00:00+00:00',
            'fixtures': {'integration/fixtures/excel-business/cases.json': 'fixture'} if business else {}}


with tempfile.TemporaryDirectory(prefix='sevra-cohort-sequence-') as temporary:
    root = Path(temporary)
    directories = [root / 'first', root / 'second']
    intervals = [runtime(2, 3), runtime(5, 6)]
    for directory, receipt in zip(directories, intervals):
        directory.mkdir()
        (directory / 'runtime.json').write_text(json.dumps(receipt))
    other = root / 'other'
    other.mkdir()
    for receipt in [runtime(0, 1), runtime(7, 8), runtime(3, 4, business=False)]:
        (other / 'runtime.json').write_text(json.dumps(receipt))
        require_consecutive(directories, intervals)
    for receipt in [runtime(3, 4), runtime(1, 3), runtime(5, 7)]:
        (other / 'runtime.json').write_text(json.dumps(receipt))
        try:
            require_consecutive(directories, intervals)
        except ValueError as error:
            assert 'intervened or overlapped' in str(error)
        else:
            raise AssertionError('A failed or overlapping business trial was ignored')
    (other / 'runtime.json').write_text(json.dumps(runtime(0, 1)))
    for candidate in [[runtime(2, 5), runtime(4, 6)], [runtime(3, 2), runtime(5, 6)]]:
        try:
            require_consecutive(directories, candidate)
        except ValueError:
            pass
        else:
            raise AssertionError('Invalid or overlapping cohort intervals passed')
    package = root / 'app.sevraapp'
    package.write_text('{"source":"model source","excelBehavior":{"source":"model calculations"}}')
    expected = hashlib.sha256(package.read_bytes()).hexdigest()
    result = {'digest': expected}
    check = {'digest': expected, 'review': {'digest': expected}}
    require_package_identity(package, result, check)
    original = package.read_bytes()
    package.write_bytes(original.replace(b'model calculations', b'changed calculations'))
    try:
        require_package_identity(package, result, check)
    except ValueError:
        pass
    else:
        raise AssertionError('A changed calculation program passed artifact identity')
    package.write_bytes(original)
    check['review']['digest'] = 'different review'
    try:
        require_package_identity(package, result, check)
    except ValueError:
        pass
    else:
        raise AssertionError('A different reviewed package passed artifact identity')

print('PASS cohort sequence: earlier/later trials and separate regression allowed; intervening failures, overlaps and invalid intervals refused')
print('PASS complete generated package identity; changed calculations and stale review refused')
print('PASS host-derived key/numeric checks; missing, duplicate, stale, reordered and misclassified probes refused')
