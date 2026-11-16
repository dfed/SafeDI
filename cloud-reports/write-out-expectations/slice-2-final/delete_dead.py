import re,subprocess,collections,sys,os,importlib.util
spec=importlib.util.spec_from_file_location("r","/root/SafeDI-regen/.claude/skills/regenerate-expectations/regenerate-expectations.py")
R=importlib.util.module_from_spec(spec); spec.loader.exec_module(R)
DECL=re.compile(r'\t*(?:private |fileprivate )?(?:static |nonisolated )*(func|let|var) (\w+)')
def read(rev):
    if rev is None:
        return {os.path.join(d,f):open(os.path.join(d,f)).read() for d,_,fs in os.walk('Tests') for f in fs if f.endswith('.swift')}
    files=subprocess.run(['git','ls-tree','-r','--name-only',rev,'Tests'],capture_output=True,text=True).stdout.split('\n')
    return {f:subprocess.run(['git','show',f'{rev}:{f}'],capture_output=True,text=True).stdout for f in files if f.endswith('.swift')}
def is_test(lines,i):
    j=i-1
    while j>=0 and lines[j].strip() and not lines[j].strip().startswith('}') and not lines[j].strip().startswith('//'):
        if '@Test' in lines[j]: return True
        j-=1
    return False
def dead(texts):
    words=collections.Counter(re.findall(r'\b\w+\b','\n'.join(texts.values())))
    out=[]
    for f,s in texts.items():
        lines=s.split('\n')
        for i,l in enumerate(lines):
            m=DECL.match(l)
            if m and words[m.group(2)]==1 and not is_test(lines,i) and l.startswith('\t') and not l.startswith('\t\t'):
                out.append((f,m.group(2),i))
    return out
base={(f,n) for f,n,_ in dead(read(sys.argv[1]))}
removed=[]
while True:
    texts=read(None)
    todo=[d for d in dead(texts) if (d[0],d[1]) not in base]
    if not todo: break
    f,name,i=todo[0]
    s=texts[f]; sf=R.SwiftFile(f,f,s); toks=sf.tokens
    lines=s.split('\n'); offs=[0]
    for l in lines: offs.append(offs[-1]+len(l)+1)
    k=next(k for k,t in enumerate(toks) if t.start>=offs[i] and t.kind=='identifier' and t.text==name)
    kind=DECL.match(lines[i]).group(1)
    if kind=='func':
        b=next(j for j in range(k,len(toks)) if toks[j].kind=='punctuation' and toks[j].text=='{' )
        # the body brace: first `{` at paren depth 0 after the parameter list
        p=next(j for j in range(k,len(toks)) if toks[j].text=='(' and toks[j].kind=='punctuation'); j=sf.matching[p]+1
        while not (toks[j].kind=='punctuation' and toks[j].text=='{'):
            j=sf.matching[j]+1 if toks[j].kind=='punctuation' and toks[j].text in '([' else j+1
        end=toks[sf.matching[j]].end
    else:
        j=k+1
        if toks[j].text=='{' or (toks[j].text==':' and any(toks[x].text=='{' and toks[x].kind=='punctuation' for x in range(j,j+12)) and not any(toks[x].text=='=' for x in range(j,j+12))):
            while not (toks[j].kind=='punctuation' and toks[j].text=='{'): j+=1
            end=toks[sf.matching[j]].end
        else:
            while not (toks[j].kind=='punctuation' and toks[j].text=='='): j+=1
            j+=1
            while True:
                t=toks[j]
                if t.kind=='punctuation' and t.text in '([{': j=sf.matching[j]; t=toks[j]
                n=toks[j+1]
                newline='\n' in s[t.end:n.start]
                cont=(n.kind=='punctuation' and n.text in '+.?:') or (t.kind=='punctuation' and t.text in '+?:=,')
                if newline and not cont: break
                j+=1
            end=toks[j].end
    # start: include doc comments/attributes above
    a=i
    while a>0 and (lines[a-1].strip().startswith('///') or lines[a-1].strip().startswith('//') or lines[a-1].strip().startswith('@')): a-=1
    endline_end=s.index('\n',end)+1
    start=offs[a]
    # one blank line removed
    if s[endline_end:endline_end+1]=='\n' and (start==0 or s[start-2:start]=='\n\n' or s[start-2:start]=='{\n'): endline_end+=1
    elif s[start-2:start]=='\n\n' and s[endline_end:].lstrip('\t').startswith('}'): start-=1
    open(f,'w').write(s[:start]+s[endline_end:])
    removed.append((f,name,i+1,s[start:endline_end].count('\n')))
for r in removed: print(*r)
