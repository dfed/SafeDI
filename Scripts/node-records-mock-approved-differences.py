#!/usr/bin/env python3
"""Compares a mock's text written from node records with the walk's text of the same mock, after the
approved mock differences (the list in the mock writer's emission review) are rewritten out of the records' text.

  node-records-mock-approved-differences.py RECORDS_FILE WALK_FILE
      prints "equal after rewrite (entries: …)" and exits 0, or the first differing line and exits 1.
  node-records-mock-approved-differences.py --pairs LIST
      LIST holds one "RECORDS_FILE<tab>WALK_FILE" per line; prints how many pairs each entry was used on,
      each pair that still differs, and exits 1 when any does.

Each rewrite is one named entry and changes the records' text only. A text that still differs after every
rewrite that applies fails; no rewrite ignores a root. Entries: 1+2 (a function handed its overrides, declared
once in the root's body: instantiated again at each call, nested, reading safeDIOverrides directly), 4 (a
wrapper's binding states its type), 6 (an unlabeled argument written "_: value"), 8 (a constant's binding
states its type), 9 (a keyword member in backticks), 10 (a public mock’s guard line once in the root’s body:
written again before each nested copy of the function it stands before).
3 (an actor's override local, placed where the walk's text declares it) and 11 (a function named apart with a
trailing underscore) read one fact from the walk's text. 5 as ruled 17:35Z (a dependency nothing fulfills, bound once by mock() in the records and first in each
function that declares it in the walk) and 17 (a local only the records read) read one too. Not rewritten, so
such a pair fails: 12. 16 (a member of a loop of builders takes its level's configuration): the level's
configuration is written out, a call of another member the level declares is a reference to it, and the
members are declared one after another. 20 (cycle kind, form c) removes the places list's declaration and the calls that
hand it on; a call of a function the caller is nested in closes on that function, and a fresh configuration
holds no override; a function reading the nearest place of its type takes the configuration that place was
entered with. 21 gives a nested cycle function the type suffix the walk declares it with.
"""
import collections
import re
import sys
import threading
MEMBERS='\x00members'
WALK_PARAMETERS={}
HANDED='\x01'
HANDS=[]
NEAREST='\x00nearest'
CONFIG='\x00configuration'
# A fresh configuration and every member path of one hold nil, by the configurations' defaulted initializers.
# A then-branch that holds an else of its own is not folded.
FOLD=re.compile(r'if let safeDIBuilder = (?:\w+\.)*\w+\.SafeDIMockConfiguration\(\)(?:\.\w+)* \{ (?:(?! else ).)*? \} else \{ (.*) \}$')
def fold_empty(line):
    return FOLD.sub(lambda m:m.group(1),line)
GUARD=re.compile(r'^\s*_ = (?:\w+\.)*\w+\.__safeDI_\w+_mock_\w+\.self //')
ALSO_USED=[]
FUNC=re.compile(r'^(\s*)((?:@Sendable nonisolated )?func )(__safeDI_[^\s(`]+|`__safeDI_[^`]+`)\((.*)\)((?: async| throws)* -> .+) \{$')
TOKEN=re.compile(r'(?<![\w.])safeDIOverrides(?![\w:])')
def block_end(lines,i):
    ind=len(lines[i])-len(lines[i].lstrip())
    close=' '*ind+'}'
    j=i+1
    while j<len(lines) and lines[j]!=close: j+=1
    return j
LOOP_ARGUMENT=re.compile(r'^__safeDI_\w+_loopConfiguration: ')
LOOP_PARAMETER=re.compile(r'(^|, )(__safeDI_\w+_loopConfiguration): [^,]*$')
def find_call_arg(line,name):
    """returns (start,end,expr) of ', safeDIOverrides: EXPR' in a call of name"""
    for m in re.finditer(r'(?<![\w.])'+re.escape(name)+r'\(',line):
        depth=0;k=m.end()-1
        for k in range(m.end()-1,len(line)):
            c=line[k]
            if c in '([': depth+=1
            elif c in ')]':
                depth-=1
                if depth==0: break
        args=line[m.end():k]
        parts=split_top(args)
        # entry 16: a member of a loop of builders is handed its level's configuration after its own
        loop=None;taken=0
        if parts and LOOP_ARGUMENT.match(parts[-1]):
            loop=parts[-1].split(': ',1)[1];taken=1
        expr=None
        if len(parts)>taken and parts[-1-taken].startswith('safeDIOverrides: '):
            expr=parts[-1-taken][len('safeDIOverrides: '):];taken+=1
        if taken:
            a=args.rfind(parts[-taken])
            sep=2 if len(parts)>taken else 0
            return m.end()+a-sep,k,expr,loop
    return None
def statement_start(lines,i,base_indent):
    """index of the first line of the statement at base indentation containing line i"""
    while len(lines[i])-len(lines[i].lstrip())>base_indent or lines[i].strip() in ('}',')'): i-=1
    return i
def stem(n):
    return n.rstrip('_') if not n.endswith('__safeDI_') else n
def split_top(t):
    parts=[];d=0;cur=''
    for i,c in enumerate(t):
        if c in '([<': d+=1
        elif c in ')]' or (c=='>' and not cur.endswith('-')): d-=1
        if c==',' and d==0: parts.append(cur.strip()); cur=''
        else: cur+=c
    if cur.strip(): parts.append(cur.strip())
    return parts
# a parameter whose type is written optional, either way Swift spells it
OPTIONAL_PARAMETER=re.compile(r': (?:.*\?|(?:Swift\.)?Optional<.*>)\s*$')
def declares_again(body,label):
    """whether a function's body declares its parameter's name again: a binding, a closure's parameter, or a
    nested function's parameter of that name"""
    name=re.escape(label.strip('`'))
    again=re.compile(r'\b(?:let|var) `?'+name+r'`?\b|\{ *(?:[\w`, ]*, *)?`?'+name+r'`?(?: *,[\w`, ]*)? in\b|\bfunc [^(]+\((?:.*, )?(?:\w+ )?`?'+name+r'`?: ')
    return any(again.search(line) for line in body)
def expand(lines,hoisted,base_indent,entered={},nearest={},visible=frozenset(),referenced=None):
    """lines: body of one function (or root) at base_indent. returns new lines."""
    out=[]
    i=0
    declared=set()
    nearest=dict(nearest)
    if referenced is None: referenced=set()
    # entry 16: the members of a loop of builders this level calls, which the walk declares together at the level
    level=set()
    for line in lines:
        if '_loopConfiguration: ' not in line: continue
        for name in hoisted:
            if name in line:
                r=find_call_arg(line,name)
                # two equal keys are one value only because every configuration in these lines was written out
                # in terms of the enclosing scope before the level's calls are collected here
                if r and r[3] is not None: level.add((name,r[2],r[3]))
    members=[]
    while i<len(lines):
        line=lines[i]
        if line.strip().startswith(NEAREST):
            # entry 20: the configuration the nearest place of a type was entered with, for the functions below
            _,key,value=line.strip().split(' ',2)
            nearest[key]=value
            i+=1; continue
        hit=None
        for name in hoisted:
            if name in line:
                r=find_call_arg(line,name)
                if r: hit=(name,)+r; break
        if not hit:
            out.append(line); i+=1; continue
        name,s,e,expr,loop=hit
        newline=line[:s]+line[e:]
        # entry 20, the places enum: how the call hands its configuration on, which the rewrite kept beside it
        key=(name,expr,loop)
        how=None
        if expr is not None and expr.startswith(HANDED):
            number,expr=expr[1:].split(HANDED,1)
            how=HANDS[int(number)]
        closes=('slot',how[1]) if how and how[0]=='entering' else name if not how else None
        if how and how[0]=='same':
            # entry 20: the function nested here calls itself at its own place; any other callee fails closed
            current=entered.get(('current',))
            if not current or current[0]!=name: raise SystemExit('a call hands its own places to another function')
            closes=current[1]
        if closes in entered:
            # entry 20: a call of a function this one is nested in closes the cycle on that function. The records
            # declare one function per place of the list, so the function's name stands for its place.
            newline=reference(newline,name,hoisted,entered.get(('kept',closes),()))
            newline=re.sub(r'(?<![\w.])'+re.escape(name)+r'(?=\()',entered[closes],newline)
            if how:
                newline=ONE_LINE_WRAPPER.sub(r'\1(\2)',newline)
                taking=ONE_LINE_CLOSURE.match(newline)
                if taking:
                    lines[i:i+1]=three_lines(taking)
                    continue
            lines[i]=newline
            mm=re.match(r'^\s*(__safeDI_\w+)\(\)$',newline)
            if mm and out and out[-1].rstrip().endswith('> {') and i+1<len(lines) and lines[i+1].strip()=='}':
                out[-1]=out[-1][:-2].rstrip()+'('+mm.group(1)+')'
                i+=2
            continue
        if key in visible:
            # entry 16: a member of the loop calls another member, which the level it is nested in declares
            referenced.add(key)
            ALSO_USED.append('16')
            newline=reference(newline,name,hoisted)
            lines[i]=newline
            mm=re.match(r'^\s*(__safeDI_\w+)\(\)$',newline)
            if mm and out and out[-1].rstrip().endswith('> {') and i+1<len(lines) and lines[i+1].strip()=='}':
                out[-1]=out[-1][:-2].rstrip()+'('+mm.group(1)+')'
                i+=2
            continue
        # instantiate
        sig,body,guard=hoisted[name]
        below=nearest
        if body and body[0].startswith(CONFIG):
            # entry 20: a function that takes the nearest place's configuration where one was entered above
            _,key,own=body[0].split(' ',2)
            expr=nearest.get(key) or (TOKEN.sub(lambda _:expr,own) if expr is not None else own)
            below=dict(nearest,**{key:expr})
            body=body[1:]
        m=FUNC.match(sig)
        if how:
            # entry 20, the places enum: a place is entered with the configuration handed, or, where the call
            # asks for the nearest of its type, with the configuration the nearest place of that type above
            # was entered with. The type is the one the function declares its configuration with.
            # The type is compared as text. Every function handed places is declared in mock()'s own body, one
            # scope, so one spelling there names one type; one type spelled two ways is missed, and the pair
            # then stays different. At run time the cast is to the struct that boxes the configuration
            # (required line for line above), so an optional configuration finds no nil of another type.
            # A slot entered anywhere above is looked up first, as the declaration's loop returns it first.
            kind,slot,asks_nearest=how
            configuration=re.search(r'(?:^|, )safeDIOverrides: (.*)$',m.group(4))
            if not configuration: raise SystemExit('a call hands places to a function that takes none')
            of_type=('type',configuration.group(1))
            if kind=='entering' and asks_nearest and of_type in nearest: expr=nearest[of_type]
            if kind!='passing':
                below=dict(below);below[of_type]=expr
        loop_parameter=LOOP_PARAMETER.search(m.group(4))
        params=LOOP_PARAMETER.sub('',m.group(4))
        params=re.sub(r'(^|, )safeDIOverrides: .*$','',params)
        handed=None;kept_labels=[]
        if loop_parameter and loop is not None:
            handed=re.compile(r'(?<![\w.])'+re.escape(loop_parameter.group(2))+r'(?![\w:])')
        # a parameter every call hands the value of its own name was a capture
        plist=split_top(params)
        callm=re.search(r'(?<![\w.])'+re.escape(name)+r'\((.*)\)',newline)
        if callm:
            alist=split_top(callm.group(1))
            keep_p=[];keep_a=[];kept_labels=[]
            for pp in plist:
                lab=pp.split(':')[0]
                ident=lab+': '+lab
                bare=lab.strip('`')+': '+lab
                absent=lab.strip('`')+': nil'
                if how and (ident in alist or bare in alist) and pp in WALK_PARAMETERS.get((base_indent,name),()):
                    # entry 20, the places enum: a function on a cycle that the walk hands this value as a
                    # parameter keeps the parameter the records declare, and every call keeps its argument, so
                    # each argument stays in the byte comparison
                    keep_p.append(pp);kept_labels.append(lab)
                elif ident in alist: alist.remove(ident)
                elif bare in alist: alist.remove(bare)
                elif absent in alist and OPTIONAL_PARAMETER.search(pp) and not declares_again(body,lab):
                    # entry 13's channel in a mock: one function with an optional parameter serves a place that
                    # hands a value and a place that hands nothing; the walk's copy for the place that hands
                    # nothing has no parameter and writes nil where the parameter was read. The nil is the
                    # literal argument of the call; a body that declares the name again is not rewritten; a read
                    # handed on to a nested call is that call's "label: nil", which goes through this rule there
                    alist.remove(absent)
                    read=re.compile(r'(?<![\w.`])'+re.escape(lab)+r'(?![\w:`])')
                    body=[read.sub('nil',x) for x in body]
                    ALSO_USED.append('13')
                else: keep_p.append(pp)
            if len(keep_p)!=len(plist):
                params=', '.join(keep_p)
                newline=newline[:callm.start(1)]+', '.join(alist)+newline[callm.end(1):]
        # the walk names a function after the binding it builds
        newname=name
        ind=' '*base_indent
        # where to insert: before the statement containing this line, within out
        k0=i
        cur0=len(line)-len(line.lstrip())
        stmt=line if cur0==base_indent else next((o for o in reversed(out) if len(o)-len(o.lstrip())==base_indent),line)
        bm=re.match(r'\s*let `?([^`:= ]+(?: [^`:= ]+)*)`?(?::| =)',stmt)
        if bm and re.match(r'^\w+$',bm.group(1)) and '__safeDI_'+bm.group(1)!=name and stem(name)!='__safeDI_'+bm.group(1):
            newname='__safeDI_'+bm.group(1)
            newline=re.sub(r'(?<![\w.])'+re.escape(name)+r'(?=\()',newname,newline)
        if guard and base_indent>8: ALSO_USED.append('10')
        inst=([ind+guard.strip()] if guard else [])+[ind+m.group(2)+newname+'('+params+')'+m.group(5)+' {']
        sub=[ (ind+'    '+b if b else b) for b in (fold_empty(TOKEN.sub(lambda _:expr,x)) if expr is not None else x for x in body)]
        if handed: sub=[handed.sub(lambda _:loop,x) for x in sub]
        if base_indent>8000: raise RecursionError('functions nest without end')
        inside=dict(entered)
        inside[('current',)]=(name,('slot',how[1]) if how and how[0]=='entering' else name if not how else None)
        if not how: inside[name]=newname
        elif how[0]=='entering':
            inside[('slot',how[1])]=newname
            inside[('kept',('slot',how[1]))]=kept_labels
        sub=expand(sub,hoisted,base_indent+4,inside,below,visible|level,referenced)
        inst+=sub+[ind+'}']
        # find statement start in out
        k=len(out)
        cur_ind=len(line)-len(line.lstrip())
        if cur_ind>base_indent:
            k=len(out)-1
            while len(out[k])-len(out[k].lstrip())>base_indent: k-=1
        if key not in declared:
            if key in level:
                # entry 16: the walk declares a loop's members one after another, in the order this level
                # binds them (its own declaration order, which a second level of the loop may not share with
                # the first), before the first is bound
                if not members: out.insert(k,MEMBERS)
                members.append((list(hoisted).index(name),inst))
            else:
                out[k:k]=inst
            declared.add(key)
        if how:
            newline=ONE_LINE_WRAPPER.sub(r'\1(\2)',newline)
            taking=ONE_LINE_CLOSURE.match(newline)
            if taking:
                lines[i:i+1]=three_lines(taking)
                continue
        lines[i]=newline
        # collapse 3-line wrapper closure
        mm=re.match(r'^\s*((?:try |await )*)(__safeDI_\w+)\(\)$',newline)
        if mm and out and out[-1].rstrip().endswith('> {') and i+1<len(lines) and lines[i+1].strip()=='}' and not mm.group(1):
            out[-1]=out[-1][:-2].rstrip()+'('+mm.group(2)+')'
            i+=2; continue
        # re-scan same line for more calls
        continue
    if members:
        at=out.index(MEMBERS)
        out[at:at+1]=[line for _,inst in members for line in inst]
    return out
# entry 20, the places enum: the records write a wrapper's closure on one line where the function is handed the
# places; once the call hands nothing, the walk hands the wrapper the function itself
def three_lines(taking):
    """entry 20, the places enum: a wrapper's closure whose call still hands arguments, on the walk's three lines"""
    return [taking.group(1)+taking.group(2)+' {',taking.group(1)+'    '+taking.group(3),taking.group(1)+'}']
ONE_LINE_CLOSURE=re.compile(r'^( *)(let .*>) \{ ((?:try |await )*__safeDI_\w+\(.+\)) \}$')
ONE_LINE_WRAPPER=re.compile(r'(>) \{ (__safeDI_\w+)\(\) \}$')
def reference(newline,name,hoisted,kept=()):
    """a call of a function declared above: an argument handed under its own name was a capture there"""
    call=re.search(r'(?<![\w.])'+re.escape(name)+r'\((.*)\)',newline)
    if not call: return newline
    labels=[part.split(':')[0] for part in split_top(FUNC.match(hoisted[name][0]).group(4))]
    labels=[label for label in labels if label not in kept]
    kept=[a for a in split_top(call.group(1)) if not any(a in (label+': '+label,label.strip('`')+': '+label) for label in labels)]
    return newline[:call.start(1)]+', '.join(kept)+newline[call.end(1):]
def unhoist(text,walk=None):
    lines=text.split('\n')
    res=[];i=0
    walk_mocks=mock_bodies(walk)[1:] if walk is not None else []
    if len(walk_mocks)!=len(mock_bodies(text))-1: walk_mocks=[]
    number=-1
    while i<len(lines):
        if MOCK.match(lines[i]):
            number+=1
            # entry 20, the places enum: the parameters the walk's functions declare in this mock, by indentation
            # and name, which decide only whether a parameter the records declare too is left declared
            WALK_PARAMETERS.clear()
            for walk_line in (walk_mocks[number].split('\n') if number<len(walk_mocks) else []):
                declared=FUNC.match(walk_line)
                if declared: WALK_PARAMETERS.setdefault((len(declared.group(1)),declared.group(3)),set()).update(split_top(declared.group(4)))
            j=i
            while not lines[j].endswith('{'): j+=1
            end=j+1
            while lines[end]!='    }': end+=1
            body=lines[j+1:end]
            hoisted={};rest=[];k=0
            while k<len(body):
                m=FUNC.match(body[k])
                if m and len(m.group(1))==8 and re.search(r'(^|, )(?:safeDIOverrides|__safeDI_\w+_loopConfiguration): ',m.group(4)):
                    e=block_end(body,k)
                    # entry 10: a public mock's guard line stands before the function that calls the mock
                    guard=rest.pop() if rest and GUARD.match(rest[-1]) else None
                    hoisted[m.group(3)]=(body[k],[b[12:] if b else b for b in body[k+1:e]],guard)
                    k=e+1
                else:
                    rest.append(body[k]);k+=1
            res+=lines[i:j+1]+expand(rest,hoisted,8)
            i=end
        else:
            res.append(lines[i]);i+=1
    return '\n'.join(res)
def e8(text,walk=None):
    # a binding whose value is built by a static method of the stated type
    def f(m):
        return m.group(1)+' = '+m.group(3) if re.search(r'else \{ (?:try |await )*'+re.escape(m.group(2))+r'\.[a-z_]\w*\(',m.group(0)+m.string[m.end():m.string.find('\n',m.end())]) else m.group(0)
    return re.sub(r'^(\s*let \w+): (.+?) = (if let safeDIBuilder = )',f,text,flags=re.M)
def e9(text,walk=None):
    # entry 9: only a member of a path that starts at safeDIOverrides, so nothing else in the text is touched
    return re.sub(r'(safeDIOverrides(?:\.\w+)*)\.`(Type|Protocol)`',r'\1.\2',text)
def e6(text,walk=None):
    # entry 6: only an argument of a call the records wrote, of a type's initializer or static method or of
    # an override: `Type(_: value)`, `Type.mock(_: value)`, `safeDIBuilder(_: value)`
    out=[]
    for line in text.split('\n'):
        position=0
        while True:
            call=E6_CALL.search(line,position)
            if not call: break
            depth=0;end=None
            for k in range(call.end()-1,len(line)):
                if line[k] in '([': depth+=1
                elif line[k] in ')]':
                    depth-=1
                    if depth==0: end=k; break
            if end is None: break
            arguments=split_top(line[call.end():end])
            renamed=', '.join(a[3:] if a.startswith('_: ') else a for a in arguments)
            if arguments and renamed!=line[call.end():end]:
                line=line[:call.end()]+renamed+line[end:]
            position=call.end()
        out.append(line)
    return '\n'.join(out)
E6_CALL=re.compile(r'(?<![\w.`])(?:(?:[A-Z]\w*\.)*[A-Z]\w*(?:\.\w+)?|safeDIBuilder)\(')
def e4(text,walk=None):
    return re.sub(r'^(\s*let \w+): ((?:Sendable)?(?:Erased)?Instantiator<.*>|(?:Sendable)?LazilyInstantiated<.*>) = \2',r'\1 = \2',text,flags=re.M)
def e20(text,walk=None):
    # entry 20, cycle kind form c: the places list's declaration and the calls that hand it on are removed.
    # What a function then reads of its configuration, and every other line, stays in the byte comparison.
    if 'indirect enum __safeDI_Places' in text: return e20_places(text)
    if 'struct __safeDI_EnteredPlaces {' not in text: return text
    lines=text.split('\n');out=[];i=0
    while i<len(lines):
        line=lines[i]
        if line.strip()=='struct __safeDI_EnteredPlaces {':
            i=block_end(lines,i)+1; continue
        if line.strip()=='let __safeDI_entered = __safeDI_EnteredPlaces()' or PLACE_LINE.match(line):
            i+=1; continue
        marked=NEAREST_LINE.match(line)
        if marked:
            out.append(marked.group(1)+NEAREST+' '+marked.group(2)+' '+marked.group(3)); i+=1; continue
        marked=NEAREST_PLACE_LINE.match(line)
        if marked:
            out.append(marked.group(1)+CONFIG+' '+marked.group(2)+' '+marked.group(3)); i+=1; continue
        line=re.sub(r'(, )?__safeDI_entered: __safeDI_EnteredPlaces(, )?',lambda m:', ' if m.group(1) and m.group(2) else '',line)
        line=re.sub(r'(, )?__safeDI_entered: __safeDI_entered(, )?',lambda m:', ' if m.group(1) and m.group(2) else '',line)
        out.append(line);i+=1
    return '\n'.join(out)
def places_declaration(sendable,enters_nearest,passes):
    """the lines a mock root declares its places with, as the generator writes them for its three arguments"""
    handed='<Handed: Sendable>' if sendable else '<Handed>'
    lines=[
        'nonisolated indirect enum __safeDI_Places: Sendable {' if sendable else 'indirect enum __safeDI_Places {',
        '    case none',
        '    case entered(slot: String?, entered: '+('any Sendable' if sendable else 'Any')+', above: __safeDI_Places)',
        '}',
        'nonisolated struct __safeDI_Entered<Configuration: Sendable>: Sendable {' if sendable else 'struct __safeDI_Entered<Configuration> {',
        '    let configuration: Configuration',
        '    var places = __safeDI_Places.none',
        '    func entering'+handed+'(_ slot: String, _ handed: Handed, nearestOfType: Bool = false) -> __safeDI_Entered<Handed> {',
        '        var nearest: __safeDI_Entered<Handed>?',
        '        var above = places',
        '        while case let .entered(enteredSlot, entered, next) = above {',
        '            if enteredSlot == slot || nearestOfType && nearest == nil, let entered = entered as? __safeDI_Entered<Handed> {',
        '                if enteredSlot == slot { return .init(configuration: entered.configuration, places: above) }',
        '                nearest = entered',
        '            }',
        '            above = next',
        '        }',
        '        let entered = __safeDI_Entered<Handed>(configuration: nearest?.configuration ?? handed)',
        '        return .init(configuration: entered.configuration, places: .entered(slot: slot, entered: entered, above: places))',
        '    }',
    ]
    if enters_nearest:
        lines+=['    func enteringNearest'+handed+'(_ handed: Handed) -> __safeDI_Entered<Handed> {',
                '        .init(configuration: handed, places: .entered(slot: nil, entered: __safeDI_Entered<Handed>(configuration: handed), above: places))',
                '    }']
    if passes:
        lines+=['    func passing'+handed+'(_ handed: Handed) -> __safeDI_Entered<Handed> {',
                '        .init(configuration: handed, places: places)',
                '    }']
    return lines+['}','let __safeDI_entered = __safeDI_Entered(configuration: ())']
ENTERED_PARAMETER=re.compile(r'(^|, )__safeDI_entered: __safeDI_Entered<(.*)>$')
HANDS_ON=re.compile(r'__safeDI_entered: __safeDI_entered\.(entering|enteringNearest|passing)\(')
SLOT=re.compile(r'^"((?:[^"\\])*)"$')
def e20_places(text):
    # entry 20, cycle kind form c with the places in an enum: the declaration is removed only where it is,
    # line for line, the text the generator writes; a function handed its configuration with the places takes
    # the configuration alone; a call that enters a place, or hands the places on, hands the configuration
    # alone, and how it handed it stays beside the argument for the function's copy to be placed by: a place
    # entered again under its slot is the enclosing function's, and a place that asks for the nearest of its
    # type takes that place's configuration. Every other line stays in the byte comparison.
    lines=text.split('\n');out=[];i=0;inside=None
    while i<len(lines):
        line=lines[i]
        if line.strip() in ('indirect enum __safeDI_Places {','nonisolated indirect enum __safeDI_Places: Sendable {'):
            indent=line[:len(line)-len(line.lstrip())]
            sendable=line.strip().startswith('nonisolated')
            for enters_nearest in (False,True):
                for passes in (False,True):
                    declaration=[indent+d for d in places_declaration(sendable,enters_nearest,passes)]
                    if lines[i:i+len(declaration)]==declaration: break
                else: continue
                break
            else: return text
            i+=len(declaration); continue
        f=FUNC.match(line)
        if f:
            parameter=ENTERED_PARAMETER.search(f.group(4))
            if parameter:
                inside=(len(f.group(1)),block_end(lines,i))
                line=f.group(1)+f.group(2)+f.group(3)+'('+f.group(4)[:parameter.start()]+parameter.group(1)+'safeDIOverrides: '+parameter.group(2)+')'+f.group(5)+' {'
        if inside and i>inside[1]: inside=None
        while True:
            call=HANDS_ON.search(line)
            if not call: break
            depth=0
            for k in range(call.end()-1,len(line)):
                if line[k] in '([': depth+=1
                elif line[k] in ')]':
                    depth-=1
                    if depth==0: break
            else: return text
            parts=split_top(line[call.end():k])
            kind=call.group(1)
            if kind=='entering':
                slot=SLOT.match(parts[0]) if parts else None
                asks=len(parts)==3 and parts[2]=='nearestOfType: true'
                if not slot or not (len(parts)==2 or asks): return text
                how=(kind,slot.group(1),asks);handed=parts[1]
            else:
                if len(parts)!=1: return text
                how=(kind,None,False);handed=parts[0]
            HANDS.append(how)
            line=line[:call.start()]+'safeDIOverrides: '+HANDED+str(len(HANDS)-1)+HANDED+handed+line[k+1:]
        # a call inside a function that hands that function's places on unchanged calls the function at its own
        # place: the cycle closes on the place the function is (kept beside the argument as 'same')
        if inside:
            same=SAME_PLACE.search(line)
            if same:
                HANDS.append(('same',None,False))
                line=line[:same.start(1)]+'safeDIOverrides: '+HANDED+str(len(HANDS)-1)+HANDED+'__safeDI_entered.configuration'+line[same.end(1):]
        if inside: line=line.replace('__safeDI_entered.configuration','safeDIOverrides')
        out.append(line);i+=1
    return '\n'.join(out)
SAME_PLACE=re.compile(r'\b__safeDI_\w+\((?:[^()]*, )?(__safeDI_entered: __safeDI_entered)\)')
NEAREST_LINE=re.compile(r'^( +)let __safeDI_entered = __safeDI_entered\.entering\((__safeDI_nearest\w+): \.init\((.+), above: __safeDI_entered\)\)$')
NEAREST_PLACE_LINE=re.compile(r'^( +)let __safeDI_place = __safeDI_entered\.\w+ \?\? \.init\(__safeDI_entered\.(__safeDI_nearest\w+)\?\.configuration \?\? (.+), above: __safeDI_entered\)$')
PLACE_LINE=re.compile(r'^ +let (?:__safeDI_place = __safeDI_entered\.\w+ \?\? \.init\(safeDIOverrides, above: __safeDI_entered\)|safeDIOverrides = __safeDI_place\.configuration|__safeDI_entered = __safeDI_place\.enteredAbove\.entering\(\w+: __safeDI_place\))$')
def mock_bodies(text):
    """the text cut before each mock function, so that a fact is read from the walk's text of the same mock"""
    parts=[[]]
    for line in text.split('\n'):
        if MOCK.match(line): parts.append([])
        parts[-1].append(line)
    return ['\n'.join(part) for part in parts]
def per_mock(rewrite):
    def whole(text,walk):
        ours=mock_bodies(text);theirs=mock_bodies(walk)
        if len(ours)!=len(theirs): return text
        return '\n'.join(rewrite(a,b) for a,b in zip(ours,theirs))
    return whole
MOCK=re.compile(r'^    (?:public )?(?:@\w+ )*static func mock\(')
LOCAL=re.compile(r'^( *)let (__safeDI_(\w+?)__(?:overrides|(?:\w+_)?safeDIBuilder)) = (safeDIOverrides(?:\.\w+)+)$')
def e3(text,walk):
    # entry 3: the walk reads an actor's overrides into a local before the actor's function, and the records
    # read a local wherever a function is handed its overrides in a closure. Which places the walk gives a
    # local is a fact read from the walk's text of the same mock; each local must find its function here.
    lines=text.split('\n')
    walk_lines=walk.split('\n')
    walk_locals=set(l.strip() for l in walk_lines if LOCAL.match(l))
    # entry 17: a local only the records declare is written out as its path only where the walk declares a
    # local of the same name in this mock, which is where an actor's function builds the same node
    walk_local_names=set(LOCAL.match(l).group(2) for l in walk_lines if LOCAL.match(l))
    i=0
    while i<len(lines):
        local=LOCAL.match(lines[i])
        if local and lines[i].strip() not in walk_locals and local.group(2) in walk_local_names:
            ALSO_USED.append('17')
            indent=len(local.group(1))
            name=re.compile(r'(?<![\w.])'+re.escape(local.group(2))+r'(?!\w)')
            del lines[i]
            k=i
            while k<len(lines) and (not lines[k].strip() or len(lines[k])-len(lines[k].lstrip())>=indent):
                again=LOCAL.match(lines[k])
                if again and again.group(2)==local.group(2):
                    # a function nested here declares the name again: its lines read its own local
                    hidden=len(again.group(1));k+=1
                    while k<len(lines) and (not lines[k].strip() or len(lines[k])-len(lines[k].lstrip())>=hidden): k+=1
                    continue
                lines[k]=name.sub(local.group(4),lines[k]);k+=1
        else: i+=1
    records_names=set(LOCAL.match(l).group(2) for l in lines if LOCAL.match(l))
    for line in walk_lines:
        local=LOCAL.match(line)
        if not local: continue
        indent,_,label,path=local.groups()
        if not local.group(2).endswith('__overrides'):
            # entry 23: in a mock whose root is an actor the walk reads a plain node's override into a local
            # before the node's function, and the records' function reads the field. That the walk does so is
            # a fact read from the walk's text; the local must find its function here, and the name must be
            # declared nowhere in the records' text of this mock.
            if local.group(2) in records_names: continue
            for i,candidate in enumerate(lines):
                f=FUNC.match(candidate)
                if not (f and f.group(1)==indent and f.group(3)=='__safeDI_'+label): continue
                if i and lines[i-1]==line: continue
                e=block_end(lines,i)
                reads=re.compile(re.escape(path)+r'(?![\w.])')
                if not any(reads.search(b) for b in lines[i+1:e]): continue
                lines[i+1:e]=[reads.sub(local.group(2),b) for b in lines[i+1:e]]
                lines.insert(i,line)
                ALSO_USED.append('23')
                break
            continue
        for i,candidate in enumerate(lines):
            f=FUNC.match(candidate)
            if not (f and f.group(1)==indent and f.group(3)=='__safeDI_'+label): continue
            if i and lines[i-1]==line: continue
            e=block_end(lines,i)
            reads=re.compile(re.escape(path)+r'(?=\.)')
            if not any(reads.search(b) for b in lines[i+1:e]): continue
            lines[i+1:e]=[reads.sub('__safeDI_'+label+'__overrides',b) for b in lines[i+1:e]]
            lines.insert(i,line)
            ALSO_USED.append('3')
            break
    return '\n'.join(lines)
def e11(text,walk):
    # entry 11: a function the records name apart with a trailing underscore, where the walk's nested
    # function of the same name hides the outer one. Whether the walk names it apart too is a fact read
    # from the walk's text of the same mock.
    for name in sorted(set(re.findall(r'func (__safeDI_\w+?_)\(',text))):
        # a name the walk tells apart by a type suffix stays apart here, for entry 21 to rename as one name
        if re.search(r'func '+re.escape(name.rstrip('_'))+r'_\w+\(',walk): continue
        if not re.search(r'(?<!\w)'+re.escape(name)+r'\(',walk):
            text=re.sub(r'(?<![\w.])'+re.escape(name)+r'(?=[(),\n])',name[:-1],text)
    return text
def takes_overrides(lines,i):
    """whether the function at line i, or a function it is nested in, has a parameter named safeDIOverrides:
    there the walk's line would read that function's configuration, not mock()'s, so the pair stays different"""
    indent=len(lines[i])-len(lines[i].lstrip())
    for k in range(i,-1,-1):
        f=FUNC.match(lines[k])
        if f and len(f.group(1))<=indent:
            if len(f.group(1))<indent or k==i:
                if re.search(r'(^|, )safeDIOverrides: ',f.group(4)): return True
                indent=len(f.group(1))
        if MOCK.match(lines[k]): break
    return False
def e5(text,walk):
    # entry 5 as ruled 17:35Z: a dependency nothing fulfills is an ordinary read, which the records bind once in
    # mock() before its nodes and the walk binds first in each function of a type that declares it. Which
    # functions those are is a fact read from the walk's text of the same mock.
    lines=text.split('\n')
    walk_lines=walk.split('\n')
    walk_at_root=set(l for l in walk_lines if UNAVAILABLE.match(l) and l.startswith('        l'))
    bound=set()
    for i in range(len(lines)-1,-1,-1):
        binding=UNAVAILABLE.match(lines[i])
        if not (binding and lines[i].startswith('        l')): continue
        bound.add(lines[i].strip())
        if lines[i] in walk_at_root: continue
        del lines[i]
        if binding.group(1)!=binding.group(3): continue
        # a binding named apart: the function that declares the label reads it under the label
        for k in range(len(lines)):
            renamed=re.match(r'^( +let \w+: '+re.escape(binding.group(2))+' = )'+re.escape(binding.group(1))+'$',lines[k])
            if renamed:
                lines[k]=renamed.group(1)+'safeDIOverrides.'+binding.group(1)
                bound.add(lines[k].strip())
    if not bound: return text
    for k in range(1,len(walk_lines)):
        if not (UNAVAILABLE.match(walk_lines[k]) and walk_lines[k].strip() in bound): continue
        # the walk binds it where the type declares it: first in the function, or after the line before it there
        indent=len(walk_lines[k])-len(walk_lines[k].lstrip())
        head=k-1
        while head>=0 and not (FUNC.match(walk_lines[head]) and len(FUNC.match(walk_lines[head]).group(1))==indent-4):
            if walk_lines[head].strip() and len(walk_lines[head])-len(walk_lines[head].lstrip())<indent: head=-1
            else: head-=1
        if head<0: continue
        i=0
        while i<len(lines):
            if lines[i]==walk_lines[head] and not takes_overrides(lines,i):
                end=block_end(lines,i)
                if head==k-1:
                    if i+1<len(lines) and lines[i+1]!=walk_lines[k]:
                        if end==i+2:
                            # the function's one expression becomes its last statement
                            only=lines[i+1]
                            lines[i+1]=only[:len(only)-len(only.lstrip())]+'return '+only.lstrip()
                        lines.insert(i+1,walk_lines[k])
                else:
                    for at in range(i+1,end):
                        if lines[at]==walk_lines[k-1] and lines[at+1]!=walk_lines[k]:
                            lines.insert(at+1,walk_lines[k]); break
            i+=1
    return '\n'.join(lines)
UNAVAILABLE=re.compile(r'^ +let (\w+): (.+\?) = safeDIOverrides\.(\w+)$')
TWO_VARIANTS_APPROVED=True
def e21(text,walk):
    # entry 21: the walk names a nested function apart by its type (__safeDI_x_Type) where the records'
    # function is __safeDI_x or __safeDI_x_, and, where the walk's function is nested out of sight of the one
    # it would hide, keeps the plain name (__safeDI_x) where the records' is __safeDI_x_. Line by line, a name
    # of the records is given the walk's name only where the walk declares a function of that name, and the
    # mock's texts must otherwise have the same lines. As ruled 2026-11-28 04:02Z the name is mapped per
    # enclosing function: every use of one declaration of the records becomes one name of the walk, so a call
    # that names another function than the walk's call does leaves the texts different. Two declarations
    # given one name must not be confused: where one is declared inside the other's block, no use of the
    # outer one may stand inside the inner one's block, and two in one block are refused.
    lines=text.split('\n');walk_lines=walk.split('\n')
    if len(lines)!=len(walk_lines): return text
    declared=set(FUNC.match(l).group(3) for l in walk_lines if FUNC.match(l))
    name=re.compile(r'(?<![\w.])__safeDI_\w+')
    def indent(i): return len(lines[i])-len(lines[i].lstrip()) if lines[i].strip() else 10**6
    def block(d):
        """the first and last line of the block a declaration at line d stands in"""
        n=indent(d);first=d;last=d
        while first>0 and indent(first-1)>=n: first-=1
        while last+1<len(lines) and indent(last+1)>=n: last+=1
        return first,last
    declarations={}
    for i,line in enumerate(lines):
        f=FUNC.match(line)
        if f: declarations.setdefault(f.group(3),[]).append((i,)+block(i))
    def declaration(x,i):
        """the declaration of x a use at line i names: the innermost block that holds both"""
        holding=[d for d in declarations.get(x,()) if d[1]<=i<=d[2]]
        return max(holding,key=lambda d:d[1]) if holding else None
    renamed={};uses={}
    returns={}
    for line in lines:
        f=FUNC.match(line)
        if f: returns.setdefault(f.group(3),set()).add(f.group(5))
    for i,(ours,theirs) in enumerate(zip(lines,walk_lines)):
        a=name.findall(ours);b=name.findall(theirs)
        if len(a)!=len(b): return text
        for x,y in zip(a,b):
            apart=y.startswith(x.rstrip('_')+'_') and len(y)>len(x)
            plain=x.endswith('_') and not x.endswith('__safeDI_') and y==x[:-1]
            # two variants of one node (the records' two functions of one label return one type): the design
            # thread, which keeps the list, reads the lead's 04:02Z ruling as covering them (04:14Z); set the
            # switch off to hold such pairs different again
            if plain and not TWO_VARIANTS_APPROVED and returns.get(x,set())&returns.get(x.rstrip('_'),set()): return text
            if not (x==y or ((apart or plain) and y in declared)): return text
            key=(x,declaration(x,i))
            if renamed.setdefault(key,y)!=y: return text
            uses.setdefault(y,{}).setdefault(key,[]).append(i)
    for y,by_declaration in uses.items():
        keys=list(by_declaration)
        for inner in keys:
            for outer in keys:
                if inner==outer: continue
                if inner[1] is None or outer[1] is None:
                    if inner[1] is None and outer[1] is None: return text
                    continue
                if inner[1][1:]==outer[1][1:]: return text
                if outer[1][1]<=inner[1][1] and inner[1][2]<=outer[1][2]:
                    if any(inner[1][1]<=i<=inner[1][2] for i in by_declaration[outer]): return text
    # what the 04:02Z and 04:25Z rulings added, counted apart: one name of the records given two names of the
    # walk, or given the plain name
    given={}
    for (x,_),y in renamed.items(): given.setdefault(x,set()).add(y)
    if any(len(names)>1 or (x.endswith('_') and x[:-1] in names) for x,names in given.items()):
        ALSO_USED.append('21 per function')
    # two variants of one node: the records' function named apart returns the type the plain one returns
    if any(x.endswith('_') and x[:-1] in names and returns.get(x,set())&returns.get(x.rstrip('_'),set()) for x,names in given.items()):
        ALSO_USED.append('21 two variants')
    out=[]
    for i,line in enumerate(lines):
        out.append(name.sub(lambda found:renamed[(found.group(0),declaration(found.group(0),i))],line))
    return '\n'.join(out)
def e18(text,walk):
    # entry 18 in a mock (lead, 2026-11-28 04:02Z): a parameter that is nil at every call is dropped. The walk's
    # function declares an optional parameter; the records' function declares none and writes nil where it
    # was read. That every call hands nil is read from the walk's text of the same mock: each call of a
    # function of that name hands the label a literal nil, or hands on the parameter itself from inside the
    # function, where nothing has declared the name again. A call that hands anything else keeps the
    # parameter, and the texts stay different. The parameter is then dropped from a copy of the walk's text
    # (signature, arguments, and nil where it was read), and only if that copy is the records' text, byte for
    # byte, is the pair equal: nothing else is forgiven.
    if text==walk: return text
    lines=walk.split('\n')
    def indent(i): return len(lines[i])-len(lines[i].lstrip())
    candidates=[]
    for line in lines:
        f=FUNC.match(line)
        if not f: continue
        for parameter in split_top(f.group(4)):
            if OPTIONAL_PARAMETER.search(parameter) and (f.group(3),parameter) not in candidates:
                candidates.append((f.group(3),parameter))
    records_declared=set()
    for line in text.split('\n'):
        f=FUNC.match(line)
        if f: records_declared.update((f.group(3),parameter) for parameter in split_top(f.group(4)))
    dropped_any=False
    for name,parameter in candidates:
        if (name,parameter) in records_declared: continue
        label=parameter.split(':')[0]
        if not re.match(r'^\w+$',label): continue
        result=drop_nil_parameter(lines,name,parameter,label)
        if result is not None:
            lines=result;dropped_any=True
    if dropped_any and '\n'.join(lines)==text: return walk
    return text
def drop_nil_parameter(lines,name,parameter,label):
    """the walk's lines without one parameter of every function of one name, or None where some call hands it a
    value, some function of the name does not declare it, or its name's scope cannot be followed"""
    lines=list(lines)
    read=re.compile(r'(?<![\w.`])'+re.escape(label)+r'(?![\w:`(])')
    binds=re.compile(r'^\s*(?:let|var) `?'+re.escape(label)+r'`?\b(.*)$')
    hides=re.compile(r'\{ *(?:[\w`, ]*, *)?`?'+re.escape(label)+r'`?(?: *,[\w`, ]*)? in\b|\bfunc (?!'+re.escape(name)+r'\()[^(]+\((?:.*, )?(?:\w+ )?`?'+re.escape(label)+r'`?: ')
    call=re.compile(r'(?<![\w.])'+re.escape(name)+r'\(')
    # a binding of the label that does not lead its statement (if let, guard let, case let, for, a tuple) is
    # not followed, and the function used as a value could be handed anything: both refuse
    elsewhere=re.compile(r'\S.*\b(?:let|var|for)\s+`?'+re.escape(label)+r'`?\b|\b(?:let|var|for)\s*\([^)]*\b'+re.escape(label)+r'\b')
    as_value=re.compile(r'(?<![\w.])'+re.escape(name)+r'(?![\w(])')
    if any(as_value.search(line) for line in lines): return None
    is_parameter=[False]*len(lines)
    declarations=[]
    for i,line in enumerate(lines):
        f=FUNC.match(line)
        if not (f and f.group(3)==name): continue
        if parameter not in split_top(f.group(4)): return None
        declarations.append(i)
        end=block_end(lines,i)
        hidden_from=None
        for k in range(i+1,end):
            if not lines[k].strip(): continue
            depth=len(lines[k])-len(lines[k].lstrip())
            if hidden_from is not None and depth<hidden_from: hidden_from=None
            if hides.search(lines[k]) or elsewhere.search(lines[k]): return None
            # a let or var of the label hides the parameter from its own line to the end of the block it
            # stands in, nested blocks included; lines before it in that block still read the parameter
            bound=binds.match(lines[k])
            if bound:
                if read.search(bound.group(1)): return None
                if hidden_from is None or depth<hidden_from: hidden_from=depth
                is_parameter[k]=False
                continue
            again=FUNC.match(lines[k])
            if again and again.group(3)==name: return None
            is_parameter[k]=hidden_from is None and not lines[k].lstrip().startswith('#sourceLocation')
    if not declarations: return None
    for i,line in enumerate(lines):
        position=0
        while True:
            found=call.search(lines[i],position)
            if not found: break
            if FUNC.match(lines[i]) and i in declarations: break
            depth=0
            for k in range(found.end()-1,len(lines[i])):
                if lines[i][k] in '([': depth+=1
                elif lines[i][k] in ')]':
                    depth-=1
                    if depth==0: break
            else: return None
            arguments=split_top(lines[i][found.end():k])
            kept=[a for a in arguments if not (a==label+': nil' or (a==label+': '+label and is_parameter[i]))]
            if len(kept)!=len(arguments)-1: return None
            replaced=lines[i][:found.end()]+', '.join(kept)
            lines[i]=replaced+lines[i][k:]
            position=len(replaced)
    for i in declarations:
        f=FUNC.match(lines[i])
        parameters=[p for p in split_top(f.group(4)) if p!=parameter]
        lines[i]=f.group(1)+f.group(2)+f.group(3)+'('+', '.join(parameters)+')'+f.group(5)+' {'
    for i in range(len(lines)):
        if is_parameter[i]: lines[i]=read.sub('nil',lines[i])
    return lines
e18=per_mock(e18)
def e26(text,walk):
    # entry 26 (lead, 2026-11-28 04:02Z): a value mock() takes under a name apart from its label is bound in
    # the function that reads it, where the walk passes it as a parameter. Read from the walk's text of the
    # same mock: every function of one name declares the parameter, and every call of that name hands the
    # label one and the same name, which is a parameter of mock() that nothing in the mock declares again, so
    # the value is one value however often it is read. In a copy of the walk's text the parameter is then
    # bound first in the function's body instead (`let label: Type = name`), and each call hands nothing; only
    # if that copy is the records' text, byte for byte, is the pair equal.
    if text==walk: return text
    lines=walk.split('\n')
    taken=set()
    for i,line in enumerate(lines):
        if MOCK.match(line):
            k=i+1
            while k<len(lines) and not lines[k].lstrip().startswith(')'):
                parameter=re.match(r'^\s*`?(\w+)`?: ',lines[k])
                if parameter: taken.add(parameter.group(1))
                k+=1
    candidates=[]
    for line in lines:
        f=FUNC.match(line)
        if not f: continue
        for parameter in split_top(f.group(4)):
            if (f.group(3),parameter) not in candidates: candidates.append((f.group(3),parameter))
    changed=False
    for name,parameter in candidates:
        label=parameter.split(':')[0]
        if not re.match(r'^\w+$',label): continue
        result=bind_handed_parameter(lines,name,parameter,label,taken)
        if result is not None:
            lines=result;changed=True
    if changed and '\n'.join(lines)==text: return walk
    return text
def declared_again(name):
    """matches a line that declares a name: a let, var or for (a tuple too), a closure's parameter, or a
    function's parameter"""
    # a function's parameter is matched only on the func line: the generator writes a nested function's
    # parameters there; mock()'s own, one per line, are not matched
    name=re.escape(name)
    return re.compile(r'\b(?:let|var|for)\s+\(?(?:[\w`, ]*,\s*)?`?'+name+r'`?\b|\{ *(?:[\w`, ]*, *)?`?'+name+r'`?(?: *,[\w`, ]*)? in\b|\bfunc [^(]+\((?:.*, )?(?:\w+ )?`?'+name+r'`?: ')
def bind_handed_parameter(lines,name,parameter,label,taken):
    """the walk's lines with one parameter of every function of one name bound in the function's body to the
    one name every call hands it, or None where the calls do not all hand one parameter of mock()"""
    lines=list(lines)
    call=re.compile(r'(?<![\w.])'+re.escape(name)+r'\(')
    declarations=[i for i,line in enumerate(lines) if FUNC.match(line) and FUNC.match(line).group(3)==name]
    if not declarations: return None
    if any(re.search(r'(?<![\w.])'+re.escape(name)+r'(?![\w(])',line) for line in lines): return None
    for i in declarations:
        if parameter not in split_top(FUNC.match(lines[i]).group(4)): return None
    handed=set()
    for i in range(len(lines)):
        if i in declarations: continue
        position=0
        while True:
            found=call.search(lines[i],position)
            if not found: break
            depth=0
            for k in range(found.end()-1,len(lines[i])):
                if lines[i][k] in '([': depth+=1
                elif lines[i][k] in ')]':
                    depth-=1
                    if depth==0: break
            else: return None
            arguments=split_top(lines[i][found.end():k])
            ours=[a for a in arguments if a.startswith(label+': ')]
            if len(ours)!=1: return None
            handed.add(ours[0][len(label)+2:])
            replaced=lines[i][:found.end()]+', '.join(a for a in arguments if a is not ours[0])
            lines[i]=replaced+lines[i][k:]
            position=len(replaced)
    if len(handed)!=1: return None
    value=handed.pop()
    if value not in taken or value==label: return None
    if any(declared_again(value).search(line) for line in lines): return None
    for i in sorted(declarations,reverse=True):
        f=FUNC.match(lines[i])
        parameters=[p for p in split_top(f.group(4)) if p!=parameter]
        lines[i]=f.group(1)+f.group(2)+f.group(3)+'('+', '.join(parameters)+')'+f.group(5)+' {'
        lines.insert(i+1,f.group(1)+'    let '+parameter+' = '+value)
    # a wrapper's closure whose call now hands nothing is the wrapper handed the function
    out=[];i=0
    while i<len(lines):
        alone=re.match(r'^\s*('+re.escape(name)+r')\(\)$',lines[i])
        if alone and out and out[-1].rstrip().endswith('> {') and i+1<len(lines) and lines[i+1].strip()=='}':
            out[-1]=out[-1][:-2].rstrip()+'('+name+')';i+=2
        else:
            out.append(lines[i]);i+=1
    return out
e26=per_mock(e26)

e21=per_mock(e21)
e3=per_mock(e3)
e5=per_mock(e5)
e11=per_mock(e11)
LOOP_INIT=re.compile(r'(__safeDI_\w+_loopConfiguration): \.init\(')
def e16_init(text,walk=None):
    """entry 16, a loop built at two levels (11-28 03:45Z): a level hands a member the first level's configuration
    as `.init(<label>: P.<label>, …)` of its own configuration P. Each member reads only those labels of it
    (checked: a read of another label leaves the text as it is, so the pair fails), so it is written as P."""
    out=[];i=0
    while True:
        m=LOOP_INIT.search(text,i)
        if not m: out.append(text[i:]); break
        depth=0;k=m.end()-1
        for k in range(m.end()-1,len(text)):
            c=text[k]
            if c in '([': depth+=1
            elif c in ')]':
                depth-=1
                if depth==0: break
        parts=split_top(text[m.end():k])
        prefixes=set();labels=set();ok=bool(parts)
        for part in parts:
            pm=re.fullmatch(r'(\w+): (.+)\.(\w+)',part)
            if not pm or pm.group(1)!=pm.group(3): ok=False; break
            labels.add(pm.group(1)); prefixes.add(pm.group(2))
        name=m.group(1)
        read=set(re.findall(r'(?<![\w.])'+re.escape(name)+r'\.(\w+)',text))
        if ok and len(prefixes)==1 and read<=labels:
            out.append(text[i:m.start()]+name+': '+prefixes.pop()); i=k+1
        else:
            out.append(text[i:m.end()]); i=m.end()
    return ''.join(out)
LOOP_STRUCT=re.compile(r'^( *)nonisolated struct (__safeDI_(\w+)_LoopOverrides): Sendable \{$')
LOOP_FIELD=re.compile(r'^ *let (\w+): (.+)$')
SENDABLE_LOOPS={}
def e19(text,walk=None):
    """entry 19, a loop of @Sendable members (11-28): the level gathers the loop's configuration into a Sendable
    struct of the labels the members read, built from the locals the level binds of its own configuration
    (`let x = safeDIOverrides.<label>`). Written in entry 16's form: the struct is removed, the level hands its
    members a stand-in P whose `P.<label>` is the local the struct was built from, and the level's calls hand
    `P.<label>` for that local. After entries 1+2 and 16 nest the members, `P.<label>` is written back as the
    local (e19_reads). Fails closed: a struct whose fields are not the built labels in order, a built value
    that is not such a local, or another use of the struct's name leaves the text as it is."""
    lines=text.split('\n');i=0
    SENDABLE_LOOPS.clear()
    while i<len(lines):
        found=LOOP_STRUCT.match(lines[i])
        if not found: i+=1; continue
        end=block_end(lines,i)
        fields=[LOOP_FIELD.match(line) for line in lines[i+1:end]]
        if not all(fields): return text
        fields=[field.group(1) for field in fields]
        struct=found.group(2);level=found.group(3)
        configuration='__safeDI_'+level+'_loopConfiguration'
        built=[k for k,line in enumerate(lines) if line.strip().startswith('let '+configuration+' = '+struct+'(')]
        if len(built)!=1: return text
        b=built[0]
        call=re.match(r'^( *)let '+configuration+' = '+struct+r'\((.*)\)$',lines[b])
        if not call: return text
        parts=split_top(call.group(2))
        if [part.split(': ',1)[0] for part in parts]!=fields: return text
        locals_={part.split(': ',1)[0]:part.split(': ',1)[1] for part in parts}
        indent=call.group(1)
        # the level function the struct is built in, and the locals it binds of its own configuration
        f=b
        while f>=0 and not (FUNC.match(lines[f]) and len(FUNC.match(lines[f]).group(1))==len(indent)-4): f-=1
        if f<0: return text
        fend=block_end(lines,f)
        for label,local in locals_.items():
            if not any(line==indent+'let '+local+' = safeDIOverrides.'+label for line in lines[f+1:b]): return text
        if len(set(locals_.values()))!=len(locals_): return text
        # a local declared a second time in the level function (a binding, a closure's or a nested function's
        # parameter) could be another value where a member reads it after nesting: refused
        if any(sum(1 for line in lines[f+1:fend] if declared_again(local).search(line))!=1 for local in locals_.values()): return text
        stand_in='__safeDI_entry19_'+level
        SENDABLE_LOOPS[stand_in]=locals_
        by_local={local:label for label,local in locals_.items()}
        for k in range(b+1,fend):
            line=lines[k]
            if configuration+': '+configuration not in line: continue
            line=line.replace(configuration+': '+configuration,configuration+': '+stand_in)
            line=re.sub(r'safeDIOverrides: (\w+)(?=, '+configuration+': )',lambda m:'safeDIOverrides: '+stand_in+'.'+by_local[m.group(1)] if m.group(1) in by_local else m.group(0),line)
            lines[k]=line
        del lines[b]
        del lines[i:end+1]
        rest='\n'.join(lines)
        if struct in rest.replace(configuration+': '+struct,''): return text
        i=0
    return '\n'.join(lines)
def e19_reads(text,walk=None):
    """entry 19: the stand-in's reads written back as the locals the level bound (any other read fails closed)"""
    for stand_in,locals_ in SENDABLE_LOOPS.items():
        def read(m):
            if m.group(1) not in locals_: raise SystemExit('a member reads a label the loop struct does not hold')
            return locals_[m.group(1)]
        text=re.sub(r'(?<![\w.])'+re.escape(stand_in)+r'\.(\w+)',read,text)
        if re.search(r'(?<![\w.])'+re.escape(stand_in)+r'(?!\w)',text): raise SystemExit('the loop stand-in is left in the text')
    return text
REWRITES=[('20',e20),('19',e19),('16',e16_init),('1+2',unhoist),('19 reads',e19_reads),('11',e11),('5',e5),('3',e3),('8',e8),('9',e9),('6',e6),('4',e4),('21',e21),('18',e18),('26',e26)]


def rewritten(text, walk):
    used = []
    for name, rewrite in REWRITES:
        del ALSO_USED[:]
        result = rewrite(text, walk)
        if result != text and name != '3':
            used.append(name)
        text = result
        for also in sorted(set(ALSO_USED)):
            used.append(also)
    return text, used


def compare(records_path, walk_path):
    records = open(records_path).read()
    walk = open(walk_path).read()
    try:
        text, used = rewritten(records, walk)
    except (Exception, SystemExit) as error:  # a shape no rewrite expects, or one a rewrite refuses, fails closed
        return used_none, 'rewrite failed: ' + repr(error)
    if text == walk:
        held = sorted(set(name for name in used if name in AWAITING_CELLS and not AWAITING_CELLS[name]))
        if held and not IGNORE_HOLDS:
            return used, 'held: the texts match after rewrite (entries: %s), but no value cell is named for: %s' % (
                ', '.join(used), ', '.join(held))
        return used, None
    ours = text.split('\n')
    theirs = walk.split('\n')
    for number in range(max(len(ours), len(theirs))):
        left = ours[number] if number < len(ours) else '<end of text>'
        right = theirs[number] if number < len(theirs) else '<end of text>'
        if left != right:
            return used, 'line %d differs after rewrite (entries: %s)\n  records: %s\n  walk:    %s' % (
                number + 1, ', '.join(used) or 'none', left, right)
    return used, 'texts differ'


used_none = []
# Lead, 2026-11-28 04:25Z: an entry approved on the condition that its values are equal counts as unclassified
# until the tests that compare those values are named. Each entry here lists those tests; an empty list holds
# every pair the entry is used on, which then prints "held" and not the words a gate reads as equal.
AWAITING_CELLS = {
    # in a mock; the test is on claude/mock-cycle-twin-parameters a2858a1a4 (merge request 1128-0436)
    '18': ['SafeDIToolNodeRecordsMockCycleWalkTests/mock_buildsTheWalksValues_whenEveryCallPassesNilForLabelBuiltAfterTheCycle'],
    '26': ['SafeDIToolMockKindsLazyCycleValueTests/mock_buildsWalksValues_whenCycleClosingCallPassesValueMockTakesUnderNameApartFromItsLabel'],
    '21 per function': [
        'SafeDIToolNodeRecordsMockCycleWalkTests/mock_buildsTheWalksValues_whenTwoBodiesNameOneVariantsFunctionApart',
        'SafeDIToolNodeRecordsMockCycleWalkTests/mock_buildsTheWalksValues_whenTheBodyThatNamesAVariantsFunctionApartIsReadBeforeTheOneThatKeepsItsName',
    ],
    # two variants of one node; the test is on claude/mock-cycle-twin-parameters f4a868ce0, and the mock writer
    # reports its recorded text holds both functions of one name and one return type (04:39Z)
    '21 two variants': ['SafeDIToolNodeRecordsMockCycleWalkTests/mock_buildsTheWalksValues_whenOneNodeIsBuiltByBuildersBeneathItsLabelHeldLazilyAndByValue'],
}
IGNORE_HOLDS = False

def main():
    global IGNORE_HOLDS
    arguments = sys.argv[1:]
    if arguments and arguments[0] == '--ignore-holds':  # the self-test's: it tests the rewrites, not the holds
        IGNORE_HOLDS = True
        arguments = arguments[1:]
    if len(arguments) == 2 and arguments[0] == '--pairs':
        counts = collections.Counter()
        failures = 0
        held = 0
        total = 0
        for line in open(arguments[1]).read().splitlines():
            if not line.strip():
                continue
            records_path, walk_path = line.split('\t')
            total += 1
            used, failure = compare(records_path, walk_path)
            if failure is None:
                for name in used:
                    counts[name] += 1
            else:
                failures += 1
                held += failure.startswith('held: ')
                print('%s: %s' % (records_path, failure))
        for name in [name for name, _ in REWRITES] + ['10', '13', '17', '21 per function', '21 two variants', '23']:
            print('entry %s: used on %d pairs' % (name, counts[name]))
        print('held for a value cell: %d pairs' % held)
        print('%d of %d pairs equal after rewrite' % (total - failures, total))
        sys.exit(1 if failures else 0)
    elif len(arguments) == 2:
        used, failure = compare(arguments[0], arguments[1])
        if failure is None:
            print('equal after rewrite (entries: %s)' % (', '.join(used) or 'none'))
            sys.exit(0)
        else:
            print(failure)
            sys.exit(1)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == '__main__':
    # a chain of functions nests as deep as the tree
    sys.setrecursionlimit(1000000)
    threading.stack_size(1024 * 1024 * 1024)
    # sys.exit in a thread ends only the thread, so the thread hands its status back
    status = [1]

    def run():
        try:
            main()
            status[0] = 0
        except SystemExit as stop:
            status[0] = stop.code if isinstance(stop.code, int) else 1

    thread = threading.Thread(target=run)
    thread.start()
    thread.join()
    sys.exit(status[0])
