import os, sys
def typ(name, decls, seam=False, root=False, conf=""):
    props=[]
    for d in decls:
        p=d.split(" let ",1)[1]; label=p.split(":")[0]; t=p.split(":",1)[1].strip(); props.append((label,t))
    params=", ".join(f"{l}: {t}" for l,t in props)
    if not props: body="public init() {}"
    else:
        body=f"public init({params}) {{\n"+"\n".join(f"        self.{l} = {l}" for l,_ in props)+"\n    }\n\n"+"\n".join(f"    {d}" for d in decls)
    attr="(generateDependencyTree: true)" if seam else "(isRoot: true)" if root else f"(fulfillingAdditionalTypes: [{conf[2:]}.self])" if conf else ""
    return f"@Instantiable{attr}\npublic struct {name}: Instantiable{conf} {{\n    {body}\n}}\n"
def modules(n):
    L=n//4
    app=[typ("Service",[]),"public protocol Api {}\n",
         typ("LiveApi",["@Received let id: Int","@Received let service: Service"],conf=", Api"),
         typ("LiveClient",["@Received let id: Int","@Received let service: Service","@Instantiated let api: any Api"],conf=", Client"),
         typ("LiveEntry",[f"@Instantiated let screen{i}Builder: Instantiator<Screen{i}>" for i in range(4)],conf=", Entry"),
         typ("Root",["@Instantiated let service: Service","@Instantiated let shell: Shell"],root=True)]
    for i in range(n):
        layer=i//4
        opened=[(layer+1)*4+j for j in range(4) if j!=i%4] if layer<L-1 else []
        app.append(typ(f"Screen{i}",["@Forwarded let id: Int","@Received let service: Service",f"@Instantiated let model{i}: Model{i}"]+[f"@Instantiated let screen{o}Builder: Instantiator<Screen{o}>" for o in opened]))
        app.append(typ(f"Model{i}",["@Received let id: Int","@Received let service: Service"]+(["@Instantiated let apiHolder: ApiHolder"] if not opened else [])))
    inner=["public protocol Entry {}\n","public protocol Client {}\n",typ("Shell",["@Instantiated let entry: any Entry"],seam=True),typ("ApiHolder",["@Instantiated let client: any Client"],seam=True)]
    return {"Inner":(inner,"Shop",[]),"App":(app,"Other",["Inner"])}
for n in (12,16,20):
    for mod,(files,pkg,deps) in modules(n).items():
        d=f"{sys.argv[1]}/s{n}/{mod}/Sources"; os.makedirs(d,exist_ok=True)
        for k,f in enumerate(files):
            open(f"{d}/F{k:03d}.swift","w").write("import SafeDI\n"+"".join(f"import {x}\n" for x in deps)+"\n"+f)
