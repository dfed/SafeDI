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
such a pair fails: 12 and 16. 20 (cycle kind, form c) removes the places list's declaration and the calls that
hand it on; a call of a function the caller is nested in closes on that function, and a fresh configuration
holds no override.
"""
import collections
import re
import sys
import threading
FOLD=re.compile(r'if let safeDIBuilder = (?:\w+\.)*\w+\.SafeDIMockConfiguration\(\)(?:\.\w+)* \{ .*? \} else \{ (.*) \}$')
def fold_empty(line):
    return FOLD.sub(lambda m:m.group(1),line)
GUARD=re.compile(r'^\s*_ = (?:\w+\.)*\w+\.__safeDI_\w+_mock_\w+\.self //')
ALSO_USED=[]
FUNC=re.compile(r'^(\s*)((?:@Sendable nonisolated )?func )(__safeDI_\w+|`__safeDI_[^`]+`)\((.*)\)((?: async| throws)* -> .+) \{$')
TOKEN=re.compile(r'(?<![\w.])safeDIOverrides(?![\w:])')
def block_end(lines,i):
    ind=len(lines[i])-len(lines[i].lstrip())
    close=' '*ind+'}'
    j=i+1
    while j<len(lines) and lines[j]!=close: j+=1
    return j
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
        if parts and parts[-1].startswith('safeDIOverrides: '):
            a=args.rfind(parts[-1])
            sep=2 if len(parts)>1 else 0
            return m.end()+a-sep,k,parts[-1][len('safeDIOverrides: '):]
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
def expand(lines,hoisted,base_indent,entered={}):
    """lines: body of one function (or root) at base_indent. returns new lines."""
    out=[]
    i=0
    declared=set()
    while i<len(lines):
        line=lines[i]
        hit=None
        for name in hoisted:
            if name in line:
                r=find_call_arg(line,name)
                if r: hit=(name,)+r; break
        if not hit:
            out.append(line); i+=1; continue
        name,s,e,expr=hit
        newline=line[:s]+line[e:]
        # entry 20: a fresh configuration, or a member of one, holds no override
        if name in entered:
            # entry 20: a call of a function this one is nested in closes the cycle on that function
            newline=re.sub(r'(?<![\w.])'+re.escape(name)+r'(?=\()',entered[name],newline)
            lines[i]=newline
            mm=re.match(r'^\s*(__safeDI_\w+)\(\)$',newline)
            if mm and out and out[-1].rstrip().endswith('> {') and i+1<len(lines) and lines[i+1].strip()=='}':
                out[-1]=out[-1][:-2].rstrip()+'('+mm.group(1)+')'
                i+=2
            continue
        # instantiate
        sig,body,guard=hoisted[name]
        m=FUNC.match(sig)
        params=re.sub(r'(^|, )safeDIOverrides: .*$','',m.group(4))
        # a parameter every call hands the value of its own name was a capture
        plist=split_top(params)
        callm=re.search(r'(?<![\w.])'+re.escape(name)+r'\((.*)\)',newline)
        if callm:
            alist=split_top(callm.group(1))
            keep_p=[];keep_a=[]
            for pp in plist:
                lab=pp.split(':')[0]
                ident=lab+': '+lab
                if ident in alist: alist.remove(ident)
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
        sub=[ (ind+'    '+b if b else b) for b in (fold_empty(TOKEN.sub(lambda _:expr,x)) for x in body)]
        sub=expand(sub,hoisted,base_indent+4,dict(entered,**{name:newname}))
        inst+=sub+[ind+'}']
        # find statement start in out
        k=len(out)
        cur_ind=len(line)-len(line.lstrip())
        if cur_ind>base_indent:
            k=len(out)-1
            while len(out[k])-len(out[k].lstrip())>base_indent: k-=1
        key=(name,expr)
        if key not in declared:
            out[k:k]=inst; declared.add(key)
        lines[i]=newline
        # collapse 3-line wrapper closure
        mm=re.match(r'^\s*((?:try |await )*)(__safeDI_\w+)\(\)$',newline)
        if mm and out and out[-1].rstrip().endswith('> {') and i+1<len(lines) and lines[i+1].strip()=='}' and not mm.group(1):
            out[-1]=out[-1][:-2].rstrip()+'('+mm.group(2)+')'
            i+=2; continue
        # re-scan same line for more calls
        continue
    return out
def unhoist(text,walk=None):
    lines=text.split('\n')
    res=[];i=0
    while i<len(lines):
        if lines[i].startswith('    static func mock(') or lines[i].startswith('    public static func mock('):
            j=i
            while not lines[j].endswith('{'): j+=1
            end=j+1
            while lines[end]!='    }': end+=1
            body=lines[j+1:end]
            hoisted={};rest=[];k=0
            while k<len(body):
                m=FUNC.match(body[k])
                if m and len(m.group(1))==8 and re.search(r'(^|, )safeDIOverrides: ',m.group(4)):
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
    if 'struct __safeDI_EnteredPlaces {' not in text: return text
    lines=text.split('\n');out=[];i=0
    while i<len(lines):
        line=lines[i]
        if line.strip()=='struct __safeDI_EnteredPlaces {':
            i=block_end(lines,i)+1; continue
        if line.strip()=='let __safeDI_entered = __safeDI_EnteredPlaces()' or PLACE_LINE.match(line):
            i+=1; continue
        line=re.sub(r'(, )?__safeDI_entered: __safeDI_EnteredPlaces(, )?',lambda m:', ' if m.group(1) and m.group(2) else '',line)
        line=re.sub(r'(, )?__safeDI_entered: __safeDI_entered(, )?',lambda m:', ' if m.group(1) and m.group(2) else '',line)
        out.append(line);i+=1
    return '\n'.join(out)
PLACE_LINE=re.compile(r'^ +let (?:__safeDI_entered = __safeDI_entered\.entering\(\w+: \.init\(safeDIOverrides(?:\.\w+)*, above: __safeDI_entered\)\)|__safeDI_place = __safeDI_entered\.\w+ \?\? \.init\(safeDIOverrides, above: __safeDI_entered\)|safeDIOverrides = __safeDI_place\.configuration|__safeDI_entered = __safeDI_place\.enteredAbove\.entering\(\w+: __safeDI_place\))$')
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
LOCAL=re.compile(r'^( *)let (__safeDI_(\w+?)__(?:overrides|safeDIBuilder)) = (safeDIOverrides(?:\.\w+)+)$')
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
                lines[k]=name.sub(local.group(4),lines[k]);k+=1
        else: i+=1
    for line in walk_lines:
        local=LOCAL.match(line)
        if not local or not local.group(2).endswith('__overrides'): continue
        indent,_,label,path=local.groups()
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
        if not (UNAVAILABLE.match(walk_lines[k]) and walk_lines[k].strip() in bound and FUNC.match(walk_lines[k-1])): continue
        i=0
        while i<len(lines):
            if lines[i]==walk_lines[k-1] and i+1<len(lines) and lines[i+1]!=walk_lines[k] and not takes_overrides(lines,i):
                if block_end(lines,i)==i+2:
                    # the function's one expression becomes its last statement
                    only=lines[i+1]
                    lines[i+1]=only[:len(only)-len(only.lstrip())]+'return '+only.lstrip()
                lines.insert(i+1,walk_lines[k])
            i+=1
    return '\n'.join(lines)
UNAVAILABLE=re.compile(r'^ +let (\w+): (.+\?) = safeDIOverrides\.(\w+)$')
e3=per_mock(e3)
e5=per_mock(e5)
e11=per_mock(e11)
REWRITES=[('20',e20),('1+2',unhoist),('11',e11),('5',e5),('3',e3),('8',e8),('9',e9),('6',e6),('4',e4)]


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
    except Exception as error:  # a shape no rewrite expects fails closed
        return used_none, 'rewrite failed: ' + repr(error)
    if text == walk:
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

def main():
    arguments = sys.argv[1:]
    if len(arguments) == 2 and arguments[0] == '--pairs':
        counts = collections.Counter()
        failures = 0
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
                print('%s: %s' % (records_path, failure))
        for name in [name for name, _ in REWRITES] + ['10', '17']:
            print('entry %s: used on %d pairs' % (name, counts[name]))
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
    thread = threading.Thread(target=main)
    thread.start()
    thread.join()
