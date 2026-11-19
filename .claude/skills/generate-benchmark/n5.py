"""python3 -I n5.py OUT LAYERS [--direct] [--per-layer-modules] [--inline]

N5: seams that instantiate seams. Shape E's graph (layers of four screens; screen i opens the three screens of the
next layer but the one at its own position), with EVERY screen a seam (generateDependencyTree: true). Every screen
forwards `id`, receives `Service`, and instantiates Model{i}; the last layer's models hold the hole `api: any Api`,
which App fills with LiveApi. Seam Home opens the first layer.
  default             screens open the next layer through `Instantiator<ScreenC>`
  --direct            screens instantiate the next layer's seams directly (`@Instantiated let screenC: ScreenC`; no id)
  --per-layer-modules each layer in its own module (Layer0 ... LayerN-1), Home in Feature
  --inline            no seams at all, one module App (2.2.0's form; output grows as 3^layers)
"""
import os, sys
out, layers = sys.argv[1], int(sys.argv[2])
direct = '--direct' in sys.argv
per_layer = '--per-layer-modules' in sys.argv
inline = '--inline' in sys.argv
count = layers * 4

def typ(name, props, attrs='@Instantiable', access='public'):
    params = [p.split(' let ')[1] for p in props]
    labels = [p.split(':')[0] for p in params]
    body = '\n'.join(f'        self.{l} = {l}' for l in labels)
    decl = '\n'.join(f'    {p}' for p in props)
    return f"{attrs}\n{access} final class {name}: Instantiable {{\n    {access} init({', '.join(params)}) {{\n{body}\n    }}\n\n{decl}\n}}\n"

files = {}
def add(module, text):
    files.setdefault(module, []).append(text)
deps = {}

seam = '@Instantiable' if inline else '@Instantiable(generateDependencyTree: true)'
core_module = 'App' if inline else 'Feature'
def layer_module(layer):
    if inline: return 'App'
    return f'Layer{layer}' if per_layer else 'Feature'
base_module = 'App' if inline else ('Base' if per_layer else 'Feature')
add(base_module, '@Instantiable public final class Service: Instantiable { public init() {} }\npublic protocol Api {}\n')
for index in range(count):
    layer = index // 4
    opened = [(layer + 1) * 4 + k for k in range(4) if k != index % 4] if layer < layers - 1 else []
    props = [] if direct else ['@Forwarded let id: Int']
    props += ['@Received let service: Service', f'@Instantiated let model{index}: Model{index}']
    if direct:
        props += [f'@Instantiated let screen{c}: Screen{c}' for c in opened]
    else:
        props += [f'@Instantiated let screen{c}Builder: Instantiator<Screen{c}>' for c in opened]
    module = layer_module(layer)
    add(module, typ(f'Screen{index}', props, seam))
    model_props = ([] if direct else ['@Received let id: Int']) + ['@Received let service: Service']
    if not opened:
        model_props.append('@Instantiated let api: any Api')
    add(module, typ(f'Model{index}', model_props))
home_module = 'App' if inline else 'Feature'
if direct:
    add(home_module, typ('Home', [f'@Instantiated let screen{k}: Screen{k}' for k in range(4)], seam))
else:
    add(home_module, typ('Home', [f'@Instantiated let screen{k}Builder: Instantiator<Screen{k}>' for k in range(4)], seam))
live_props = ([] if direct else ['@Received let id: Int']) + ['@Received let service: Service']
add('App', typ('LiveApi', live_props, '@Instantiable(fulfillingAdditionalTypes: [Api.self])').replace('final class LiveApi: Instantiable', 'final class LiveApi: Api, Instantiable'))
add('App', typ('Root', ['@Instantiated let service: Service', '@Instantiated let home: Home'], '@Instantiable(isRoot: true)'))

if inline:
    modules = ['App']
elif per_layer:
    modules = ['Base'] + [f'Layer{l}' for l in reversed(range(layers))] + ['Feature', 'App']
    deps['Base'] = []
    for l in range(layers):
        deps[f'Layer{l}'] = ['Base'] + [f'Layer{m}' for m in range(l + 1, layers)]
    deps['Feature'] = ['Base'] + [f'Layer{m}' for m in range(layers)]
    deps['App'] = ['Base', 'Feature'] + [f'Layer{m}' for m in range(layers)]
else:
    modules = ['Feature', 'App']
    deps['Feature'] = []
    deps['App'] = ['Feature']
for module in modules:
    os.makedirs(f'{out}/{module}/Sources', exist_ok=True)
    imports = ''.join(f'import {d}\n' for d in deps.get(module, [])) + 'import SafeDI\n\n'
    with open(f'{out}/{module}/Sources/{module}.swift', 'w') as f:
        f.write(imports + '\n'.join(files.get(module, [])))
    if module in deps:
        with open(f'{out}/{module}/dependencies.txt', 'w') as f:
            f.write('\n'.join(deps[module]) + '\n')
    if not inline and module != 'App' and module != 'Base':
        with open(f'{out}/{module}/Sources/SafeDIConfiguration.swift', 'w') as f:
            f.write('import SafeDI\n\n#SafeDIConfiguration(generatePlainDependencyTreeInitializers: true)\n')
with open(f'{out}/modules.txt', 'w') as f:
    f.write(' '.join(modules) + '\n')
