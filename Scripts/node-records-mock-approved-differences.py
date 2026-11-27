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
states its type), 9 (a keyword member in backticks), 10 (a public mock's guard line once in the root's body).
Not rewritten, so such a pair fails: 3 (an actor's override local), 11, 12 and the unavailable-dependency read.
"""
import collections
import re
import sys
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
def expand(lines,hoisted,base_indent):
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
        # instantiate
        sig,body=hoisted[name]
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
        inst=[ind+m.group(2)+newname+'('+params+')'+m.group(5)+' {']
        sub=[ (ind+'    '+b if b else b) for b in (TOKEN.sub(lambda _:expr,x) for x in body)]
        sub=expand(sub,hoisted,base_indent+4)
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
def unhoist(text):
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
                    hoisted[m.group(3)]=(body[k],[b[12:] if b else b for b in body[k+1:e]])
                    k=e+1
                else:
                    rest.append(body[k]);k+=1
            res+=lines[i:j+1]+expand(rest,hoisted,8)
            i=end
        else:
            res.append(lines[i]);i+=1
    return '\n'.join(res)
def e8(text):
    # a binding whose value is built by a static method of the stated type
    def f(m):
        return m.group(1)+' = '+m.group(3) if re.search(r'else \{ (?:try |await )*'+re.escape(m.group(2))+r'\.[a-z_]\w*\(',m.group(0)+m.string[m.end():m.string.find('\n',m.end())]) else m.group(0)
    return re.sub(r'^(\s*let \w+): (.+?) = (if let safeDIBuilder = )',f,text,flags=re.M)
def e9(text):
    return re.sub(r'(safeDIOverrides(?:\.\w+)*)\.`(Type|Protocol)`',r'\1.\2',text)
def e10(text):
    lines=text.split('\n');out=list(lines)
    for i,l in enumerate(lines):
        m=re.match(r'^        _ = ((?:\w+\.)*\w+)\.__safeDI_\w+_mock_\w+\.self //',l)
        if not m: continue
        T=m.group(1)
        for j in range(i+1,len(lines)):
            f=FUNC.match(lines[j])
            if lines[j]=='    }': break
            if f and f.group(5).endswith('-> '+T) and len(f.group(1))>8:
                ind=f.group(1)
                out=lines[:i]+lines[i+1:j]+[ind+l.strip()]+lines[j:]
                return e10('\n'.join(out))
    return text
def e6(text):
    return re.sub(r'([(,] ?)_: ',r'\1',text)
def e4(text):
    return re.sub(r'^(\s*let \w+): ((?:Sendable)?(?:Erased)?Instantiator<.*>|(?:Sendable)?LazilyInstantiated<.*>) = \2',r'\1 = \2',text,flags=re.M)
REWRITES=[('1+2',unhoist),('8',e8),('9',e9),('10',e10),('6',e6),('4',e4)]


def rewritten(text):
    used = []
    for name, rewrite in REWRITES:
        result = rewrite(text)
        if result != text:
            used.append(name)
            text = result
    return text, used


def compare(records_path, walk_path):
    records = open(records_path).read()
    walk = open(walk_path).read()
    try:
        text, used = rewritten(records)
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

if __name__ == '__main__':
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
        for name, _ in REWRITES:
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
