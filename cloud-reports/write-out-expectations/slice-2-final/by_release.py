import sys,importlib.util
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
W=load("w","/root/SafeDI-regen/.claude/skills/regenerate-expectations/write-out-expectations.py"); R=W.regenerator
records_dir='/root/.cache/RecS2/base'
header=R.read_header(records_dir)
records=[r for r in R.read_records(records_dir) if r["kind"]=="generation"]
path='Tests/SafeDIToolSeamTests/SafeDIToolUnreadTypeAccessTests.swift'
def rewrite(test, line, has_integration):
    source=open(path).read(); sf=R.SwiftFile(path,path,source); st=W.Structure(sf); toks=sf.tokens
    call=next(i for i,t in enumerate(toks) if t.kind=='identifier' and t.text=='expect' and sf.line_of(t.start)==line)
    opening=call+1; closing=st.closing(opening)
    a,b=st.elements(opening)[0]
    eq=next(p for p in range(a,b) if st.parent[p]==opening and st.is_punctuation(p,'=') and st.is_punctuation(p+1,'='))
    indentation='\t\t\t'
    gens={}
    for r in records:
        if r.get("testName","").startswith(test+'(') and r.get("module")=="Feature":
            gens.setdefault((r.get("integration"),r["inputsDigest"]),{})[r["outputName"]]=W.file_parts(r["content"],header,[])
    def release(files):
        text=''.join(v for _,parts in files.values() for k,v in parts)
        if 'was active, but it is inactive' in text: return 'true'
        if 'was inactive, but it is active' in text: return 'false'
        return None
    cases={}
    for (integration,digest),files in gens.items():
        cases.setdefault((integration,W.value_source(files,"files",indentation+'\t')),set()).add(release(files))
    lines=[]
    for (integration,src),rel in sorted(cases.items(), key=lambda c:(c[0][0],sorted(map(str,c[1])))):
        if None in rel or len(rel)==2:
            assert len([1 for (i,_) in cases if i==integration])==1, (integration, rel)
            pattern='_'
        else: pattern=next(iter(rel))
        label=f'(.{integration}, {pattern})' if has_integration else pattern
        lines.append(f'{indentation}case {label}:\n{indentation}\t{src}')
    subject='(integration, isReleaseConfiguration)' if has_integration else 'isReleaseConfiguration'
    stmt_start=source.rindex('\n',0,toks[call].start)+1
    decl=f'{indentation}let expectedFiles: [String: String] = switch {subject} {{\n'+'\n'.join(lines)+f'\n{indentation}}}\n'
    source=source[:stmt_start]+decl+source[stmt_start:toks[eq+2].start]+'expectedFiles'+source[toks[closing].start:]
    open(path,'w').write(source); print(test, [(i,r) for (i,_),r in cases.items()])
for test,line,hi in reversed([("generate_takesPublicTier_whenAnotherFileDeclaresTypeWhereMockConditionIsInactive",3804,True),("generate_takesPublicTier_whenAnotherFileDeclaresTypeWhereMockConditionIsInactiveAndSeamReceivesItOnlyIfAvailable",3828,True),("generate_takesPublicTier_whenSeamsOwnModuleDeclaresTypeInMockOnlyBlockAndUnderNegatedMockCondition",3853,False)]):
    rewrite(test,line,hi)
