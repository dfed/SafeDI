#!/usr/bin/env python3
"""measure.py TOOL[,legacy] SHAPE_DIR OUT [heaptrack]: runs generate per module; prints wall, cpu, max rss (MB) and, with heaptrack, peak heap."""
import os, sys, subprocess, time, re
tool, shape, out = sys.argv[1], sys.argv[2], sys.argv[3]
legacy = tool.endswith(',legacy'); tool = tool.split(',')[0]
heap = len(sys.argv) > 4
os.makedirs(out, exist_ok=True)
wall = cpu = rss = 0; peak = 0
for line in open(f'{shape}/modules.txt'):
    parts = line.split()
    if not parts: continue
    module, deps = parts[0], (parts[1].split(',') if len(parts) > 1 else [])
    files = sorted(os.path.join(dp, f) for dp, _, fs in os.walk(f'{shape}/{module}') for f in fs if f.endswith('.swift'))
    open(f'{out}/{module}.csv', 'w').write(','.join(files))
    args = [tool, 'generate', f'{out}/{module}.csv', '--combined-output', f'{out}/{module}.generated.swift', '--module-info-output', f'{out}/{module}.safedi', '--active-compilation-conditions', 'DEBUG']
    if not legacy: args += ['--module-name', module, '--package-name', 'Bench']
    if deps:
        open(f'{out}/{module}.deps.csv', 'w').write(','.join(f'{out}/{d}.safedi' for d in deps))
        args += ['--dependent-module-info-file-path', f'{out}/{module}.deps.csv']
    pre = ['heaptrack', '-o', f'{out}/{module}.ht'] if heap else []
    t = time.monotonic(); p = subprocess.Popen(pre + args, stdout=open(f'{out}/{module}.log', 'wb'), stderr=subprocess.STDOUT); _, st, u = os.wait4(p.pid, 0)
    if st != 0: print('FAILED', module, open(f'{out}/{module}.log').read()[-2000:]); sys.exit(1)
    wall += time.monotonic() - t; cpu += u.ru_utime + u.ru_stime; rss = max(rss, u.ru_maxrss / (1024 * 1024 if sys.platform == 'darwin' else 1024))
    if heap:
        ht = [f for f in os.listdir(out) if f.startswith(f'{module}.ht')][0]
        o = subprocess.run(['heaptrack_print', '-f', f'{out}/{ht}', '-s', '0', '-p', '0', '-a', '0', '-T', '0', '-n', '0', '-l', '0'], capture_output=True, text=True).stdout
        m = re.search(r'peak heap memory consumption: ([\d.]+)([KMG])', o)
        if m:
            v = float(m.group(1)) * {'K': 1/1024, 'M': 1, 'G': 1024}[m.group(2)]; peak = max(peak, v)
        os.remove(f'{out}/{ht}')
print(f'{os.path.basename(shape)} wall {wall:.2f} cpu {cpu:.2f} rss {rss:.0f}MB' + (f' heap {peak:.0f}MB' if heap else ''))
