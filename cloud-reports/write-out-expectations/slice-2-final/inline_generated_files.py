"""Inlines calls of generatedFiles(module:integration:imports:rootFiles:) at the given FILE:LINE sites."""
import re,sys,importlib.util
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
W=load("w","/root/SafeDI-regen/.claude/skills/regenerate-expectations/write-out-expectations.py")
R=W.regenerator

def literal_indentation(source, token):
    text=source[token.start:token.end]
    assert text.startswith('"""\n'), text[:40]
    last=text.rsplit('\n',1)[1]
    assert last.strip()=='"""', last
    return last[:len(last)-3]

def process(path, line_numbers):
    for line_number in sorted(line_numbers, reverse=True):
        source=open(path).read()
        sf=R.SwiftFile(path,path,source); st=W.Structure(sf); toks=sf.tokens
        call=next(i for i,t in enumerate(toks) if t.kind=='identifier' and t.text in ('generatedFiles','expectGeneratedCode') and sf.line_of(t.start)==line_number and st.is_punctuation(i+1,'('))
        first=st.callee_start(call+1); opening=call+1; closing=st.closing(opening)
        labels={}
        for a,b in st.elements(opening):
            assert st.is_punctuation(a+1,':')
            labels[toks[a].text]=(a+2,b)
        module=st.source(*labels['module']).strip('"')
        integration=st.source(*labels['integration']) if 'integration' in labels else '.moduleInfo'
        ia,ib=labels['imports']
        imports=[toks[i].text.strip('"') if toks[i].kind!='string' else source[toks[i].start:toks[i].end].strip('"') for i in range(ia+1,ib) if toks[i].kind=='string']
        ra,rb=labels['rootFiles']
        assert st.is_punctuation(ra,'[') and st.closing(ra)==rb
        entries={}
        for a,b in st.elements(ra):
            assert toks[a].kind=='string' and st.is_punctuation(a+1,':'), st.source(a,b)[:50]
            entries[source[toks[a].start:toks[a].end].strip('"')]=(a+2,b)
        def with_imports(a,b):
            """(source of the entry's value with the import blocks inside each literal, whether it is one literal)"""
            strings=[i for i in range(a,b+1) if toks[i].kind=='string' and st.parent[i]==st.parent[a] and source[toks[i].start:toks[i].end].startswith('"""')]
            text=source[toks[a].start:toks[b].end]
            if not strings:
                if not imports:
                    return text, False
                block=''.join(f'#if canImport({name})\nimport {name}\n#endif\n' for name in imports)
                return '"""\n'+block+'\n\\('+text+')\n"""', True
            out=text; offset=toks[a].start
            for i in reversed(strings):
                indentation=literal_indentation(source,toks[i])
                block=''.join(f'{indentation}#if canImport({name})\n{indentation}import {name}\n{indentation}#endif\n' for name in imports)+('\n' if imports else '')
                at=toks[i].start-offset+4
                out=out[:at]+block+out[at:]
            return out, (len(strings)==1 and a==b)
        def content(a,b):
            assert a==b and toks[a].kind=='string', "an entry that is not one literal cannot be joined: "+st.source(a,b)[:60]
            text=with_imports(a,b)[0] if False else source[toks[a].start:toks[a].end]
            indentation=literal_indentation(source,toks[a])
            body=text[4:text.rindex('\n')]
            return [l[len(indentation):] if l.strip() else '' for l in body.split('\n')]
        def value(a,b):
            text,single=with_imports(a,b)
            return 'generatedFileHeader + '+(text if single else '('+text+')')
        names=sorted(entries)
        def combined():
            if len(names)==1:
                return f'"{module}.swift": '+value(*entries[names[0]])
            lines=[]
            for name in imports:
                lines+= [f'#if canImport({name})',f'import {name}','#endif']
            if imports: lines.append('')
            for index,name in enumerate(names):
                if index: lines.append('')
                lines+=content(*entries[name])
            return f'"{module}.swift": generatedFileHeader + """\n'+'\n'.join(lines)+'\n"""'
        def per_type():
            return ', '.join(f'"{name}+SafeDI.swift": '+value(*entries[name]) for name in names)
        if integration=='.moduleInfo':
            replacement='['+combined()+']'
        elif integration=='.swiftPackagePlugin':
            replacement='['+per_type()+']'
        elif len(names)==1:
            replacement=f'[{integration} == .moduleInfo ? "{module}.swift" : "{names[0]}+SafeDI.swift": '+value(*entries[names[0]])+']'
        else:
            replacement=f'({integration} == .moduleInfo ? [{combined()}] : [{per_type()}])'
        if toks[call].text=='expectGeneratedCode':
            replacement=f'expectGeneratedFiles({st.source(*labels["of"])}.modules["{module}"]?.generatedFiles, {replacement})'
        source=source[:toks[first].start]+replacement+source[toks[closing].end:]
        open(path,'w').write(source)
        print(path,line_number,len(names),integration)
for argument in sys.argv[1:]:
    path,lines=argument.split(':',1)
    process(path,[int(l) for l in lines.split(',')])
