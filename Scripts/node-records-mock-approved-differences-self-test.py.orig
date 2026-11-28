#!/usr/bin/env python3
"""Self-test of node-records-mock-approved-differences.py: for each rewrite that restructures text (entries 13, 16,
20 in its three forms, 21 and 23), one real pair the rewrite makes equal, and hand edits of the records' text after each of which the pair
must differ. Prints one line per case and exits 1 when a pair is not equal before an edit or still equal after one.

  node-records-mock-approved-differences-self-test.py
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, 'node-records-mock-approved-differences.py')
FIXTURES = os.path.join(HERE, 'node-records-mock-approved-differences-fixtures')


def once(old, new):
    def edit(text):
        if text.count(old) < 1:
            raise SystemExit('the fixture no longer holds: ' + old)
        return text.replace(old, new, 1)
    return edit


def swapped(first, second):
    def edit(text):
        if text.count(first) != 1 or text.count(second) != 1:
            raise SystemExit('the fixture no longer holds one of each: ' + first)
        return text.replace(first, '\0').replace(second, first).replace('\0', second)
    return edit


CASES = [
    ('16', 'a member hands another member its own configuration under the wrong label',
     once('__safeDI_bBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration.bBuilder,',
          '__safeDI_bBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration.cBuilder,')),
    ('16', 'the level hands a member another level configuration',
     once('__safeDI_cBuilder(safeDIOverrides: safeDIOverrides.cBuilder, __safeDI_Holder_loopConfiguration: safeDIOverrides)',
          '__safeDI_cBuilder(safeDIOverrides: safeDIOverrides.cBuilder, __safeDI_Holder_loopConfiguration: safeDIOverrides.aBuilder)')),
    ('16', 'an override read of a configuration that is not fresh is dropped',
     once('return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(aBuilder) } else { C(aBuilder: aBuilder) }',
          'return C(aBuilder: aBuilder)')),
    ('16', 'two members’ bodies are swapped',
     swapped('return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(aBuilder, cBuilder) } else { B(aBuilder: aBuilder, cBuilder: cBuilder) }',
             'return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(aBuilder) } else { C(aBuilder: aBuilder) }')),
    ('20', 'a call hands another place’s configuration',
     once('__safeDI_roomBuilder(safeDIOverrides: safeDIOverrides.roomBuilder, __safeDI_entered: __safeDI_entered)',
          '__safeDI_roomBuilder(safeDIOverrides: safeDIOverrides.otherRoomBuilder, __safeDI_entered: __safeDI_entered)')),
    ('20', 'an override read of a configuration that is not fresh is dropped',
     once('return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(otherHomeBuilder) } else { Room(otherHomeBuilder: otherHomeBuilder) }',
          'return Room(otherHomeBuilder: otherHomeBuilder)')),
    ('20', 'a function no longer reads the nearest place of its type',
     once('.init(__safeDI_entered.__safeDI_nearest1?.configuration ?? safeDIOverrides, above: __safeDI_entered)',
          '.init(safeDIOverrides, above: __safeDI_entered)')),
    ('20', 'the nearest place is entered with another configuration',
     once('entering(__safeDI_nearest1: .init(safeDIOverrides, above: __safeDI_entered))',
          'entering(__safeDI_nearest1: .init(safeDIOverrides.roomBuilder, above: __safeDI_entered))')),
    ('20-places', 'a call that hands the places on hands another configuration',
     once('__safeDI_entered.passing(__safeDI_entered.configuration.porch)',
          '__safeDI_entered.passing(__safeDI_entered.configuration.roomBuilder)')),
    ('20-places', 'a call no longer asks for the nearest place of its type',
     once('__safeDI_entered.entering("otherHomeBuilder", Home.SafeDIMockConfiguration(), nearestOfType: true)',
          '__safeDI_entered.entering("otherHomeBuilder", Home.SafeDIMockConfiguration())')),
    ('20-places', 'the root’s call enters no nearest place',
     once('__safeDI_entered.enteringNearest(safeDIOverrides.homeBuilder)',
          '__safeDI_entered.passing(safeDIOverrides.homeBuilder)')),
    ('20-places', 'a call enters its place under another function’s slot',
     once('__safeDI_entered.entering("otherHomeBuilder", Home.SafeDIMockConfiguration(), nearestOfType: true)',
          '__safeDI_entered.entering("roomBuilder", Home.SafeDIMockConfiguration(), nearestOfType: true)')),
    ('20-places', 'a line of the places’ declaration is changed',
     once('if enteredSlot == slot { return .init(', 'if enteredSlot != slot { return .init(')),
    ('20-places', 'an override read of a configuration that is not fresh is dropped',
     once('return if let safeDIBuilder = __safeDI_entered.configuration.safeDIBuilder { safeDIBuilder(shedBuilder) } else { Porch(shedBuilder: shedBuilder) }',
          'return Porch(shedBuilder: shedBuilder)')),
    ('20-parameter', 'the closing call hands another value',
     once('__safeDI_screenBuilder(session: session, __safeDI_entered: __safeDI_entered.entering("screenBuilder", Screen.SafeDIMockConfiguration()))',
          '__safeDI_screenBuilder(session: Session(), __safeDI_entered: __safeDI_entered.entering("screenBuilder", Screen.SafeDIMockConfiguration()))')),
    ('20-parameter', 'the function on the cycle reads the outer value where the walk’s is handed one',
     once('func __safeDI_screenBuilder(session: Session, __safeDI_entered:', 'func __safeDI_screenBuilder(__safeDI_entered:')),
    ('21', 'a call hands another place’s configuration',
     once('__safeDI_childBuilder_(safeDIOverrides: safeDIOverrides.childBuilder,',
          '__safeDI_childBuilder_(safeDIOverrides: safeDIOverrides.otherBuilder,')),
    ('21', 'an override read of a configuration that is not fresh is dropped',
     once('return if let safeDIBuilder = safeDIOverrides.safeDIBuilder { safeDIBuilder(childBuilder) } else { Grandchild(childBuilder: childBuilder) }',
          'return Grandchild(childBuilder: childBuilder)')),
    ('21', 'a call names the other type’s function of the same label',
     once('__safeDI_childBuilder_(safeDIOverrides: safeDIOverrides.childBuilder,',
          '__safeDI_childBuilder(safeDIOverrides: safeDIOverrides.childBuilder,')),
    ('21', 'the closing call names the other type’s function of the same label',
     once('__safeDI_childBuilder(safeDIOverrides: Child.SafeDIMockConfiguration(),',
          '__safeDI_childBuilder_(safeDIOverrides: Child.SafeDIMockConfiguration(),')),
    ('23-ancestor', 'the function built again reads another configuration’s override',
     once('return if let safeDIBuilder = __safeDI_entered.configuration.safeDIBuilder { safeDIBuilder(worker) } else { Store(worker: worker) }',
          'return if let safeDIBuilder = __safeDI_entered.configuration.worker.safeDIBuilder { safeDIBuilder(worker) } else { Store(worker: worker) }')),
    ('23-ancestor', 'the place built again no longer asks for the nearest of its type',
     once('__safeDI_entered.entering("storeBuilder", Store.SafeDIMockConfiguration(), nearestOfType: true)',
          '__safeDI_entered.entering("storeBuilder", Store.SafeDIMockConfiguration())')),
    ('23', 'a call hands another place’s override',
     once('let r0: R0 = __safeDI_r0(x0: x0, safeDIOverrides: safeDIOverrides.r0)',
          'let r0: R0 = __safeDI_r0(x0: x0, safeDIOverrides: safeDIOverrides.r1)')),
    ('23', 'the override read is dropped',
     once('return if let safeDIBuilder = safeDIOverrides { safeDIBuilder(r0x0) } else { R0(r0x0: r0x0) }',
          'return R0(r0x0: r0x0)')),
    ('13', 'the place that hands nothing hands a value of that name',
     once('__safeDI_model(token: nil, safeDIOverrides: safeDIOverrides.model)',
          '__safeDI_model(token: token, safeDIOverrides: safeDIOverrides.model)')),
    ('13', 'the function declares the parameter’s name again and reads that',
     once('            let api: any Api = if let safeDIBuilder = safeDIOverrides.api { safeDIBuilder(token) }',
          '            let token: Token? = nil\n            let api: any Api = if let safeDIBuilder = safeDIOverrides.api { safeDIBuilder(token) }')),
    ('13', 'the function writes nil where it read its parameter',
     once('LiveApi(token: token)', 'LiveApi(token: nil)')),
]


def equal_after_rewrite(records, walk_path):
    with tempfile.NamedTemporaryFile('w', suffix='.records', delete=False) as file:
        file.write(records)
    try:
        return subprocess.run([sys.executable, SCRIPT, file.name, walk_path], capture_output=True, timeout=60).returncode == 0
    except subprocess.TimeoutExpired:
        return False
    finally:
        os.unlink(file.name)


failures = 0
for entry in sorted(set(case[0] for case in CASES)):
    records = open(os.path.join(FIXTURES, entry + '.records')).read()
    walk_path = os.path.join(FIXTURES, entry + '.walk')
    if equal_after_rewrite(records, walk_path):
        print('entry %s: the pair is equal after rewrite' % entry)
    else:
        print('entry %s: FAILED, the pair differs before any edit' % entry)
        failures += 1
    for _, name, edit in [case for case in CASES if case[0] == entry]:
        if equal_after_rewrite(edit(records), walk_path):
            print('entry %s: FAILED, still equal when %s' % (entry, name))
            failures += 1
        else:
            print('entry %s: differs when %s' % (entry, name))
sys.exit(1 if failures else 0)
