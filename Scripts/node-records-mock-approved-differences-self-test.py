#!/usr/bin/env python3
"""Self-test of node-records-mock-approved-differences.py: for each rewrite that restructures text (entries 13, 16 with a
loop at two levels, 19, 20 in its four forms, 21 and 23), one real pair the rewrite makes equal, and hand edits of the records' text after each of which the pair
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


def last_two_swapped(first, second):
    """swaps the last occurrence of first with the last occurrence of second, which follows it"""
    def edit(text):
        a = text.rfind(first)
        b = text.rfind(second)
        if a < 0 or b != a + len(first):
            raise SystemExit('the fixture no longer holds the two in a row: ' + first)
        return text[:a] + second + first + text[b + len(second):]
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
    ('20-left-out', 'the call along the edge the configurations leave out no longer enters its place left out',
     once('__safeDI_entered.leavingOut.entering("alphaBuilder", Alpha.SafeDIMockConfiguration())',
          '__safeDI_entered.entering("alphaBuilder", Alpha.SafeDIMockConfiguration())')),
    ('20-left-out', 'a function left out hands the configuration it would hand where it is not',
     once('__safeDI_entered.passing(__safeDI_entered.isLeftOut ? Gamma.SafeDIMockConfiguration() : __safeDI_entered.configuration.gamma)',
          '__safeDI_entered.passing(__safeDI_entered.configuration.gamma)')),
    ('20-left-out', 'a line of the places’ declaration is changed',
     once('entered.isLeftOut ? handed : entered.configuration', 'entered.isLeftOut ? entered.configuration : handed')),
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
    ('18', 'a call of the walk hands the parameter a value',
     once('__safeDI_t3Builder(session: session, logger: nil)',
          '__safeDI_t3Builder(session: session, logger: Logger(t3Builder: t3Builder))'), 'walk'),
    ('18', 'the walk’s function reads another name where the records write nil',
     once('T3(session: session, logger: logger, t0Builder: t0Builder, t4Builder: t4Builder)',
          'T3(session: session, logger: session, t0Builder: t0Builder, t4Builder: t4Builder)'), 'walk'),
    ('18', 'the walk binds the label in an if let, so its reads are not the parameter’s',
     once('return if let safeDIBuilder = safeDIOverrides.t3Builder.safeDIBuilder {',
          'return if let logger = Optional(Logger?.none), let safeDIBuilder = safeDIOverrides.t3Builder.safeDIBuilder {'), 'walk'),
    ('18', 'the records write a value where the parameter was read',
     once('T3(session: session, logger: nil, t0Builder: t0Builder, t4Builder: t4Builder)',
          'T3(session: session, logger: Logger(), t0Builder: t0Builder, t4Builder: t4Builder)')),
    ('21-scopes', 'a call in the second parent names the first parent’s function',
     once('__safeDI_aBuilder_(safeDIOverrides: safeDIOverrides.aBuilder)',
          '__safeDI_aBuilder(safeDIOverrides: safeDIOverrides.aBuilder)')),
    ('21-scopes', 'a parent hands the shared function another override',
     once('__safeDI_aBuilder_(safeDIOverrides: __safeDI_entered.configuration.aBuilder)',
          '__safeDI_aBuilder_(safeDIOverrides: __safeDI_entered.configuration.bBuilder)')),
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
    ('16-two-levels', 'a level’s configuration of the loop leaves out a label a member reads',
     once('.init(aBuilder: safeDIOverrides.aBuilder, bBuilder: safeDIOverrides.bBuilder)', '.init(aBuilder: safeDIOverrides.aBuilder)')),
    ('16-two-levels', 'a level’s configuration of the loop hands one label another’s value',
     once('.init(aBuilder: safeDIOverrides.aBuilder, bBuilder: safeDIOverrides.bBuilder)', '.init(aBuilder: safeDIOverrides.bBuilder, bBuilder: safeDIOverrides.aBuilder)')),
    ('16-two-levels', 'the second level binds its members in the first level’s order',
     last_two_swapped('            let bBuilder = Instantiator<B> {\n                __safeDI_bBuilder(safeDIOverrides: safeDIOverrides.bBuilder, __safeDI_First_loopConfiguration: .init(aBuilder: safeDIOverrides.aBuilder, bBuilder: safeDIOverrides.bBuilder))\n            }\n',
                      '            let aBuilder = Instantiator<A> {\n                __safeDI_aBuilder(safeDIOverrides: safeDIOverrides.aBuilder, __safeDI_First_loopConfiguration: .init(aBuilder: safeDIOverrides.aBuilder, bBuilder: safeDIOverrides.bBuilder))\n            }\n')),
    ('19', 'the loop’s struct is built with one label’s local under another label',
     once('bBuilder: __safeDI_bBuilder__safeDIBuilder, cBuilder: __safeDI_cBuilder__safeDIBuilder)', 'bBuilder: __safeDI_cBuilder__safeDIBuilder, cBuilder: __safeDI_bBuilder__safeDIBuilder)')),
    ('19', 'a member hands another member its configuration under the wrong label',
     once('__safeDI_cBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration.cBuilder,', '__safeDI_cBuilder(safeDIOverrides: __safeDI_Holder_loopConfiguration.bBuilder,')),
    ('19', 'the loop’s struct leaves out a field it is built with',
     once('            let cBuilder: (@Sendable (SendableInstantiator<A>) -> C)?\n', '')),
    ('19', 'the level binds a member’s local from another label',
     once('let __safeDI_cBuilder__safeDIBuilder = safeDIOverrides.cBuilder', 'let __safeDI_cBuilder__safeDIBuilder = safeDIOverrides.bBuilder')),
    ('20-self', 'the call that hands a function’s places on unchanged names another function',
     once('{ __safeDI_screenBuilder(__safeDI_entered: __safeDI_entered) }', '{ __safeDI_stepBuilder(__safeDI_entered: __safeDI_entered) }')),
    ('20-self', 'the call enters another place instead of handing its own on',
     once('{ __safeDI_screenBuilder(__safeDI_entered: __safeDI_entered) }', '{ __safeDI_screenBuilder(__safeDI_entered: __safeDI_entered.entering("detail", __safeDI_entered.configuration)) }')),
    ('26', 'a call of the walk hands the parameter another value',
     once('__safeDI_screenBuilder(mark: mark_Mark)', '__safeDI_screenBuilder(mark: mark)'), 'walk'),
    ('26', 'the records’ function binds another name',
     once('let mark: Mark = mark_Mark', 'let mark: Mark = other_Mark')),
    ('26', 'the root’s call enters the place with another configuration',
     once('__safeDI_entered.entering("screenBuilder", safeDIOverrides.screenBuilder)',
          '__safeDI_entered.entering("screenBuilder", safeDIOverrides.hubBuilder)')),
    ('24', 'the function that calls the marked one is no longer marked',
     once('@Sendable nonisolated func __safeDI_aBuilder(', 'func __safeDI_aBuilder(')),
    ('24', 'the moved function is marked @Sendable only',
     once('@Sendable nonisolated func __safeDI_bBuilder(', '@Sendable func __safeDI_bBuilder(')),
    ('24', 'the moved function is isolated to the main actor',
     once('@Sendable nonisolated func __safeDI_bBuilder(', '@MainActor func __safeDI_bBuilder(')),
    ('28', 'the one function is named for a later property of the level',
     lambda text: text.replace('__safeDI_t2()', '__safeDI_t0()')),
    ('28', 'a copy of the walk differs from the function by more than its name',
     once('            return Z1080_T0(lazyT2: lazyT2)\n        }\n        let t0', '            return Z1080_T0(lazyT2: lazyT2 )\n        }\n        let t0'), 'walk'),
    ('28', 'a declaration between the function and a later property is a name the function reads',
     once('        let t2: Z1080_T0 = __safeDI_t2()\n', '        let t2: Z1080_T0 = __safeDI_t2()\n        let lazyT2 = 0\n'), 'both'),
    ('28', 'a later property calls another function',
     once('        let t0: Z1080_T0 = __safeDI_t2()', '        let t0: Z1080_T0 = __safeDI_t7Builder()')),
    ('20-classes', 'a place is entered, and closed on, under a slot beyond the words the declaration holds',
     lambda text: text.replace('__safeDI_entered.entering(0, ', '__safeDI_entered.entering(64, ')),
    ('20-classes', 'a call no longer asks for the nearest place of its type',
     once('__safeDI_entered.entering(2, Home.SafeDIMockConfiguration(), nearestOfType: true)',
          '__safeDI_entered.entering(2, Home.SafeDIMockConfiguration())')),
    ('20-classes', 'a call enters its place under another function’s slot',
     once('__safeDI_entered.entering(2, Home.SafeDIMockConfiguration(), nearestOfType: true)',
          '__safeDI_entered.entering(1, Home.SafeDIMockConfiguration(), nearestOfType: true)')),
    ('24-named-apart', 'the @Sendable function that reads the moved function is plain in both texts',
     once('@Sendable nonisolated func __safeDI_t4Builder(', 'func __safeDI_t4Builder('), 'both'),
    ('24-named-apart', 'the moved function, named apart, is marked @Sendable only',
     once('@Sendable nonisolated func __safeDI_anyT5Builder_(', '@Sendable func __safeDI_anyT5Builder_(')),
    ('27', 'the function is reached only by calls that have no configuration',
     once('__safeDI_entered.entering(1, safeDIOverrides.childBuilder)', '__safeDI_entered.leavingOut.entering(1, safeDIOverrides.childBuilder)')),
    ('27', 'the call with no configuration hands one that is not fresh',
     once('__safeDI_entered.leavingOut.entering(1, Child.SafeDIMockConfiguration())', '__safeDI_entered.leavingOut.entering(1, Child.SafeDIMockConfiguration(state: nil))')),
    ('27', 'the argument reads a field of another name',
     once('Child(parentBuilder: parentBuilder, state: __safeDI_entered.configuration.state)', 'Child(parentBuilder: parentBuilder, state: __safeDI_entered.configuration.title)')),
]


def edited_walk(walk_path, edit):
    """a temporary copy of a fixture's walk text after an edit, for a case whose fact is read from the walk"""
    file = tempfile.NamedTemporaryFile('w', suffix='.walk', delete=False)
    file.write(edit(open(walk_path).read()))
    file.close()
    return file.name


def equal_after_rewrite(records, walk_path):
    with tempfile.NamedTemporaryFile('w', suffix='.records', delete=False) as file:
        file.write(records)
    try:
        return subprocess.run([sys.executable, SCRIPT, '--ignore-holds', file.name, walk_path], capture_output=True, timeout=60).returncode == 0
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
    for case in [case for case in CASES if case[0] == entry]:
        name, edit = case[1], case[2]
        if len(case) == 4:  # the edit is of the walk's text, or ('both') of both texts
            other_walk = edited_walk(walk_path, edit)
            still_equal = equal_after_rewrite(edit(records) if case[3] == 'both' else records, other_walk)
            os.unlink(other_walk)
        else:
            still_equal = equal_after_rewrite(edit(records), walk_path)
        if still_equal:
            print('entry %s: FAILED, still equal when %s' % (entry, name))
            failures += 1
        else:
            print('entry %s: differs when %s' % (entry, name))
sys.exit(1 if failures else 0)
